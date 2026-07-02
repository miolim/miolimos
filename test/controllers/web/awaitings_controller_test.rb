require "test_helper"

class AwaitingsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @hans = HumanActor.create!(
      name: "Hans", email: "hans-aw-#{SecureRandom.hex(3)}@t.local",
      password: "secretsecret"
    )
    grant(@hans, "Awaiting", %w[read create update delete])
    grant(@hans, "Task",     %w[read create update delete])
    grant(@hans, "Topic",    %w[read update])
    grant(@hans, "Contact",  %w[read])

    post "/login", params: { email: @hans.email, password: "secretsecret" }
  end

  # #739 (Hans): Quick-Add ohne Titel → Platzhalter + Cursor ins (jetzt
  # editierbare) Titelfeld, statt an der Titel-Pflicht zu scheitern.
  test "#739 Quick-Add Wartepunkt ohne Titel legt Platzhalter an + fokussiert Titelfeld" do
    assert_difference -> { Awaiting.count }, 1 do
      post "/awaitings",
           params: { quick_create: "1", awaiting: { title: "" } },
           headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end
    assert_response :ok
    aw = Awaiting.order(:created_at).last
    assert_equal "Neuer Wartepunkt", aw.title
    assert_includes @response.body, 'data-focus-after-add="title"'
    # editierbares Titelfeld (awaiting[title]) ist in der Card
    assert_includes @response.body, 'name="awaiting[title]"'
  end

  test "GET /awaitings lists open awaitings by urgency" do
    Awaiting.create!(creator: @hans, title: "A", follow_up_at: Date.today + 1)
    Awaiting.create!(creator: @hans, title: "B", follow_up_at: Date.today + 5)
    get "/awaitings"
    assert_response :success
    assert_includes @response.body, "A"
    assert_includes @response.body, "B"
  end

  test "POST /awaitings creates awaiting with topics" do
    topic = Topic.create!(name: "T", slug: "t-#{SecureRandom.hex(3)}", creator: @hans)

    assert_difference -> { Awaiting.count }, 1 do
      post "/awaitings", params: {
        awaiting: { title: "Warte auf X", follow_up_at: (Date.today + 7).iso8601,
                    topic_ids: [topic.id] }
      }
    end
    awaiting = Awaiting.order(:id).last
    assert_equal "Warte auf X", awaiting.title
    assert_includes awaiting.topics, topic
  end

  test "POST /awaitings with topic_id param attaches that topic" do
    topic = Topic.create!(name: "T", slug: "t-#{SecureRandom.hex(3)}", creator: @hans)
    post "/awaitings",
         params: { topic_id: topic.id, awaiting: { title: "Warte Y" } }
    awaiting = Awaiting.order(:id).last
    assert_equal "Warte Y", awaiting.title
    assert_includes awaiting.topics, topic
    # follow_up_at default = today + 7
    assert_equal Date.today + 7, awaiting.follow_up_at
  end

  test "POST /awaitings/:id/resolve sets status to resolved" do
    a = Awaiting.create!(creator: @hans, title: "x", follow_up_at: Date.today + 3)
    post "/awaitings/#{a.id}/resolve", params: { resolution_note: "Got it" }
    assert a.reload.resolved?
    assert_equal "Got it", a.resolution_note
  end

  test "POST /awaitings/:id/create_task creates task and resolves awaiting" do
    topic   = Topic.create!(name: "T", slug: "t-#{SecureRandom.hex(3)}", creator: @hans)
    trigger = Task.create!(title: "trigger", creator: @hans)
    a = Awaiting.create!(creator: @hans, title: "w", follow_up_at: Date.today + 3,
                         task: trigger)
    AwaitingTopic.create!(awaiting: a, topic: topic)

    assert_difference -> { Task.count }, 1 do
      assert_difference -> { TaskDependency.count }, 1 do
        post "/awaitings/#{a.id}/create_task", params: { title: "Next step" }
      end
    end
    new_task = Task.where(title: "Next step").first
    assert new_task.open?
    assert_includes new_task.topics, topic
    assert TaskDependency.exists?(predecessor: trigger, successor: new_task)
    assert a.reload.resolved?
  end

  test "DELETE /awaitings/:id" do
    a = Awaiting.create!(creator: @hans, title: "x", follow_up_at: Date.today + 3)
    delete "/awaitings/#{a.id}"
    assert_redirected_to awaitings_path
    refute Awaiting.exists?(a.id)
  end

  test "POST /tasks/:id/create_awaiting creates awaiting linked to task" do
    task = Task.create!(title: "t", creator: @hans)
    topic = Topic.create!(name: "T", slug: "t-#{SecureRandom.hex(3)}", creator: @hans)
    TaskTopic.create!(task: task, topic: topic)

    assert_difference -> { Awaiting.count }, 1 do
      post "/tasks/#{task.id}/create_awaiting",
           params: { description: "Ergebnis X", follow_up_at: (Date.today + 5).iso8601 }
    end
    awaiting = Awaiting.order(:id).last
    assert_equal task.id, awaiting.task_id
    # Tasks#create_awaiting schreibt derzeit noch in .title via description-Param.
    assert_equal "Ergebnis X", awaiting.title
    assert_includes awaiting.topics, topic
  end

  test "POST /awaitings/:id/topics attaches a topic (chip-style)" do
    topic = Topic.create!(name: "T", slug: "t-#{SecureRandom.hex(3)}", creator: @hans)
    a = Awaiting.create!(creator: @hans, title: "x", follow_up_at: Date.today + 3)
    post "/awaitings/#{a.id}/topics", params: { topic_id: topic.id }
    assert_includes a.reload.topics, topic
  end

  test "DELETE /awaitings/:id/topics/:id detaches the topic" do
    topic = Topic.create!(name: "T", slug: "t-#{SecureRandom.hex(3)}", creator: @hans)
    a = Awaiting.create!(creator: @hans, title: "x", follow_up_at: Date.today + 3)
    AwaitingTopic.create!(awaiting: a, topic: topic)
    delete "/awaitings/#{a.id}/topics/#{topic.slug}"
    assert_empty a.reload.topics
  end
end
