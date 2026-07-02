require "test_helper"

class TaskTagsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @hans = HumanActor.create!(
      name: "Hans", email: "hans-tags-#{SecureRandom.hex(3)}@t.local",
      password: "secretsecret"
    )
    grant(@hans, "Task", %w[read create update delete])

    post "/login", params: { email: @hans.email, password: "secretsecret" }

    @task = Task.create!(title: "Tag-Test", creator: @hans, assignee: @hans,
                         status: :open, tags: [])
  end

  test "POST adds a tag via create_with" do
    assert_difference -> { @task.reload.tags.size }, 1 do
      post "/tasks/#{@task.id}/tags",
           params: { create_with: "bug" },
           headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end
    assert_response :ok
    assert_includes @task.reload.tags, "bug"
    assert_includes @response.body, "task_tags_chips_#{@task.id}"
  end

  test "POST adds a tag via tag_id (existing)" do
    @task.update!(tags: ["alpha"])
    post "/tasks/#{@task.id}/tags",
         params: { tag_id: "feature" },
         headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_response :ok
    assert_equal %w[alpha feature], @task.reload.tags.sort
  end

  test "POST normalizes to lowercase + strip" do
    post "/tasks/#{@task.id}/tags",
         params: { create_with: "  BUG  " },
         headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_equal ["bug"], @task.reload.tags
  end

  test "POST is idempotent for duplicate tag" do
    @task.update!(tags: ["bug"])
    assert_no_difference -> { @task.reload.tags.size } do
      post "/tasks/#{@task.id}/tags",
           params: { create_with: "bug" },
           headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end
    assert_response :ok
  end

  test "POST 422 on empty tag" do
    post "/tasks/#{@task.id}/tags",
         params: { create_with: "   " },
         headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_response :unprocessable_entity
  end

  test "DELETE removes a tag" do
    @task.update!(tags: %w[bug feature chore])
    assert_difference -> { @task.reload.tags.size }, -1 do
      delete "/tasks/#{@task.id}/tags/feature",
             headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end
    assert_response :ok
    assert_equal %w[bug chore], @task.reload.tags.sort
  end

  test "DELETE idempotent for missing tag" do
    @task.update!(tags: %w[bug])
    assert_no_difference -> { @task.reload.tags.size } do
      delete "/tasks/#{@task.id}/tags/nonexistent",
             headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end
  end

  test "GET /tasks/suggest_tags returns distinct existing tags" do
    Task.create!(title: "T1", creator: @hans, status: :open, tags: %w[bug urgent])
    Task.create!(title: "T2", creator: @hans, status: :open, tags: %w[bug feature])
    Task.create!(title: "T3", creator: @hans, status: :open, tags: %w[urgent])

    get "/tasks/suggest_tags", headers: { "Accept" => "application/json" }
    assert_response :ok
    items = JSON.parse(response.body)["items"]
    slugs = items.map { |i| i["slug"] }.sort
    assert_equal %w[bug feature urgent], slugs
    assert items.all? { |i| i["slug"] == i["label"] }
  end

  test "GET /tasks/suggest_tags filters by q" do
    Task.create!(title: "T1", creator: @hans, status: :open, tags: %w[bug urgent])
    Task.create!(title: "T2", creator: @hans, status: :open, tags: %w[feature])
    get "/tasks/suggest_tags", params: { q: "bug" }, headers: { "Accept" => "application/json" }
    items = JSON.parse(response.body)["items"]
    assert_equal ["bug"], items.map { |i| i["slug"] }
  end
end
