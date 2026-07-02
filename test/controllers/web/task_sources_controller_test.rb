require "test_helper"

class TaskSourcesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @hans = HumanActor.create!(
      name: "Hans", email: "hans-ts-#{SecureRandom.hex(3)}@t.local",
      password: "secretsecret"
    )
    grant(@hans, "Task",   %w[read create update])
    grant(@hans, "Source", %w[read create update])
    post "/login", params: { email: @hans.email, password: "secretsecret" }

    @task = Task.create!(title: "Tu was", creator: @hans, assignee: @hans, status: :open)
    @source = Source.create!(
      slug: "smith-2020-test-#{SecureRandom.hex(3)}",
      title: "Smith (2020): Test", csl_type: "book", creator: @hans
    )
  end

  test "POST with source_id (slug) links existing Source to task" do
    assert_difference -> { @task.reload.task_sources.count }, 1 do
      post "/tasks/#{@task.id}/sources",
           params: { source_id: @source.slug },
           headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end
    assert_response :ok
    assert_includes @task.reload.sources, @source
    assert_includes @response.body, "task_sources_chips_#{@task.id}"
  end

  test "POST is idempotent — second link does not create duplicate" do
    TaskSource.create!(task: @task, source: @source)
    assert_no_difference -> { @task.reload.task_sources.count } do
      post "/tasks/#{@task.id}/sources",
           params: { source_id: @source.slug },
           headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end
    assert_response :ok
  end

  test "DELETE unlinks source with undo toast" do
    TaskSource.create!(task: @task, source: @source)

    assert_difference -> { @task.reload.task_sources.count }, -1 do
      delete "/tasks/#{@task.id}/sources/#{@source.slug}",
             headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end
    assert_response :ok
    assert_includes @response.body, "toast_stack"
    assert_includes @response.body, @source.title
  end
end
