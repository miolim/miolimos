require "test_helper"

class ActorViewsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @hans = HumanActor.create!(
      name: "Hans", email: "hans-views-#{SecureRandom.hex(3)}@t.local",
      password: "secretsecret"
    )
    grant(@hans, "Actor", %w[read update])
    grant(@hans, "Task",  %w[read create])  # damit wir Tasks anlegen können
    grant(@hans, "KnowledgeItem", %w[read create])

    post "/login", params: { email: @hans.email, password: "secretsecret" }
  end

  test "POST creates an actor_view for a Task" do
    task = Task.create!(title: "Trackable", creator: @hans, status: :open)
    assert_difference -> { ActorView.count }, 1 do
      post "/actor_views",
           params: { viewable_type: "Task", viewable_id: task.id, duration_ms: 5000 },
           headers: { "Accept" => "application/json" }
    end
    assert_response :ok
    json = JSON.parse(response.body)
    assert json["id"]
    assert_equal 5000, json["duration_ms"]
    assert_equal false, json["was_edited"]
  end

  test "POST dedupes within 60s — updates duration to max" do
    task = Task.create!(title: "Dedupe", creator: @hans, status: :open)
    post "/actor_views",
         params: { viewable_type: "Task", viewable_id: task.id, duration_ms: 3000 },
         headers: { "Accept" => "application/json" }

    assert_no_difference -> { ActorView.count } do
      post "/actor_views",
           params: { viewable_type: "Task", viewable_id: task.id, duration_ms: 8000 },
           headers: { "Accept" => "application/json" }
    end
    view = ActorView.last
    assert_equal 8000, view.duration_ms
  end

  test "POST flips was_edited from false → true within the same session" do
    task = Task.create!(title: "Edited", creator: @hans, status: :open)
    post "/actor_views",
         params: { viewable_type: "Task", viewable_id: task.id, duration_ms: 3000, was_edited: false },
         headers: { "Accept" => "application/json" }
    post "/actor_views",
         params: { viewable_type: "Task", viewable_id: task.id, duration_ms: 4000, was_edited: true },
         headers: { "Accept" => "application/json" }
    assert_equal 1, ActorView.count
    assert ActorView.last.was_edited
  end

  test "POST returns 422 for unknown viewable_type" do
    post "/actor_views",
         params: { viewable_type: "Unicorn", viewable_id: 1, duration_ms: 3000 },
         headers: { "Accept" => "application/json" }
    assert_response :unprocessable_entity
  end

  test "POST returns 422 for missing viewable_id" do
    post "/actor_views",
         params: { viewable_type: "Task", duration_ms: 3000 },
         headers: { "Accept" => "application/json" }
    assert_response :unprocessable_entity
  end

  test "POST stores session_token if provided" do
    task = Task.create!(title: "Sess", creator: @hans, status: :open)
    post "/actor_views",
         params: { viewable_type: "Task", viewable_id: task.id,
                   duration_ms: 3000, session_token: "abc123" },
         headers: { "Accept" => "application/json" }
    assert_equal "abc123", ActorView.last.session_token
  end

  test "ActorView.distinct_recent returns one row per (type, id)" do
    task = Task.create!(title: "DistinctTask", creator: @hans, status: :open)
    # Zwei Views mit 90s Abstand → zwei Datensätze:
    ActorView.create!(actor: @hans, viewable_type: "Task", viewable_id: task.id,
                      viewed_at: 2.minutes.ago, duration_ms: 3000)
    ActorView.create!(actor: @hans, viewable_type: "Task", viewable_id: task.id,
                      viewed_at: Time.current, duration_ms: 5000)
    rows = ActorView.distinct_recent.where(actor_id: @hans.id, viewable_type: "Task").to_a
    assert_equal 1, rows.size, "distinct_recent sollte nur einen Eintrag pro Entity liefern"
  end
end
