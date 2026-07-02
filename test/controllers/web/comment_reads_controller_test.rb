require "test_helper"

class CommentReadsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @hans = HumanActor.create!(name: "Hans",
      email: "hans-cr-#{SecureRandom.hex(3)}@t.local", password: "secretsecret")
    grant(@hans, "TaskComment", %w[read create update])
    grant(@hans, "Task", %w[read create])
    @agent = AgentActor.create!(name: "AgentX-#{SecureRandom.hex(3)}", description: "x", active: true)
    @task = Task.create!(title: "TC-test", creator: @hans, assignee: @agent)
    @c1 = @task.comments.create!(actor: @agent, body: "First",  published_at: Time.current)
    @c2 = @task.comments.create!(actor: @agent, body: "Second", published_at: Time.current)
    @c3 = @task.comments.create!(actor: @agent, body: "Third",  published_at: Time.current)
    post "/login", params: { email: @hans.email, password: "secretsecret" }
  end

  test "POST /comment_reads markiert einzelnen Comment fuer current_actor" do
    assert_difference -> { CommentRead.where(actor_id: @hans.id).count }, 1 do
      post "/comment_reads", params: { comment_id: @c1.id },
                             headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end
    assert_response :success
    assert CommentRead.exists?(actor_id: @hans.id, task_comment_id: @c1.id)
    refute CommentRead.exists?(actor_id: @hans.id, task_comment_id: @c2.id),
           "Andere Comments duerfen nicht mit-markiert werden"
  end

  test "POST /comment_reads mit comment_ids[] markiert Bulk" do
    assert_difference -> { CommentRead.where(actor_id: @hans.id).count }, 3 do
      post "/comment_reads", params: { comment_ids: [@c1.id, @c2.id, @c3.id] },
                             headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end
    assert_response :success
  end

  test "POST /comment_reads ist idempotent (gleicher Comment zweimal)" do
    CommentRead.create!(actor_id: @hans.id, task_comment_id: @c1.id, read_at: Time.current)
    assert_no_difference -> { CommentRead.where(actor_id: @hans.id).count } do
      post "/comment_reads", params: { comment_id: @c1.id },
                             headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end
    assert_response :success
  end

  test "POST /comment_reads ohne comment_id liefert no_content" do
    assert_no_difference -> { CommentRead.count } do
      post "/comment_reads", params: {},
                             headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end
    assert_response :no_content
  end

  # ─── Regression: TasksController#show markiert NICHT mehr auto ───

  test "GET /tasks/:id markiert Comments NICHT mehr automatisch als gelesen" do
    assert_no_difference -> { CommentRead.where(actor_id: @hans.id).count } do
      get task_path(@task)
    end
    # #163 Phase 6c: /tasks/:id leitet jetzt zur Stack-Variante um
    # (`/tasks?stack=list:tasks,task:X`). Wichtig ist hier nur, dass
    # ohne Auto-Mark-as-read durchkommt, der Redirect ist Beigemuese.
    assert_response :redirect
  end
end
