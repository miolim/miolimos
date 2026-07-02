require "test_helper"

class TaskCommentsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @hans = HumanActor.create!(
      name: "Hans", email: "hans-tc-#{SecureRandom.hex(3)}@t.local",
      password: "secretsecret"
    )
    grant(@hans, "Task", %w[read create update delete])
    post "/login", params: { email: @hans.email, password: "secretsecret" }

    @task = Task.create!(title: "Tu was", creator: @hans, assignee: @hans, status: :open)
  end

  test "POST creates comment and renders thread + form streams" do
    assert_difference -> { @task.reload.comments.count }, 1 do
      post "/tasks/#{@task.id}/comments",
           params: { body: "  erster Kommentar  " },
           headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end
    assert_response :ok
    assert_equal "erster Kommentar", @task.comments.last.body
    assert_includes @response.body, "task_comments_#{@task.id}"
    assert_includes @response.body, "task_comment_form_#{@task.id}"
  end

  test "POST with blank body returns toast and creates nothing" do
    assert_no_difference -> { @task.reload.comments.count } do
      post "/tasks/#{@task.id}/comments",
           params: { body: "   " },
           headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end
    assert_response :ok
    assert_includes @response.body, "toast_stack"
  end

  test "GET edit on last own comment renders edit form" do
    c = @task.comments.create!(actor: @hans, body: "v1")
    get "/tasks/#{@task.id}/comments/#{c.id}/edit"
    assert_response :ok
    assert_includes @response.body, "task_comment_body_#{c.id}"
  end

  test "PATCH update changes body and re-renders body frame" do
    c = @task.comments.create!(actor: @hans, body: "v1")
    patch "/tasks/#{@task.id}/comments/#{c.id}", params: { body: "v2" }
    assert_response :ok
    assert_equal "v2", c.reload.body
    assert_includes @response.body, "task_comment_body_#{c.id}"
  end

  test "PATCH update with blank body keeps original and renders toast" do
    c = @task.comments.create!(actor: @hans, body: "v1")
    patch "/tasks/#{@task.id}/comments/#{c.id}",
          params: { body: "   " },
          headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_response :ok
    assert_equal "v1", c.reload.body
    assert_includes @response.body, "toast_stack"
  end

  test "PATCH update on non-last comment is forbidden" do
    # Beide Comments müssen veröffentlicht sein — #181 erlaubt das
    # Bearbeiten von Drafts unabhängig von ihrer Position im Thread.
    older = @task.comments.create!(actor: @hans, body: "older", published_at: 1.minute.ago)
    @task.comments.create!(actor: @hans, body: "newer", published_at: Time.current)
    patch "/tasks/#{@task.id}/comments/#{older.id}", params: { body: "edited" }
    assert_response :forbidden
    assert_equal "older", older.reload.body
  end

  test "DELETE removes last own comment" do
    c = @task.comments.create!(actor: @hans, body: "ach lass das doch")
    assert_difference -> { @task.reload.comments.count }, -1 do
      delete "/tasks/#{@task.id}/comments/#{c.id}",
             headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end
    assert_response :ok
    assert_includes @response.body, "task_comment_#{c.id}"
  end

  test "DELETE on someone else's comment is forbidden" do
    other = HumanActor.create!(
      name: "Eve", email: "eve-#{SecureRandom.hex(3)}@t.local",
      password: "secretsecret"
    )
    c = @task.comments.create!(actor: other, body: "fremd")
    delete "/tasks/#{@task.id}/comments/#{c.id}"
    assert_response :forbidden
    assert TaskComment.exists?(c.id)
  end

  test "GET show renders body frame for cancel-after-edit" do
    c = @task.comments.create!(actor: @hans, body: "abc")
    get "/tasks/#{@task.id}/comments/#{c.id}"
    assert_response :ok
    assert_includes @response.body, "task_comment_body_#{c.id}"
    assert_includes @response.body, "abc"
  end
end
