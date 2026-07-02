require "test_helper"

class Api::V1::TasksControllerTest < ActionDispatch::IntegrationTest
  setup do
    @creator = create_human
    @agent = AgentActor.create!(name: "ta-#{SecureRandom.hex(3)}", description: "t")
    grant(@agent, "Task", %w[read create update delete])
    @headers = { "Authorization" => "Bearer #{@agent.api_token}" }
  end

  test "index returns tasks" do
    Task.create!(title: "T1", creator: @creator)
    Task.create!(title: "T2", creator: @creator)
    get "/api/v1/tasks", headers: @headers
    body = JSON.parse(response.body)
    assert body["data"].size >= 2
  end

  test "index filters by status" do
    done = Task.create!(title: "done", creator: @creator, status: :done)
    Task.create!(title: "open", creator: @creator, status: :open)
    get "/api/v1/tasks", params: { status: "done" }, headers: @headers
    titles = JSON.parse(response.body)["data"].map { |t| t["title"] }
    assert_equal ["done"], titles.uniq
  end

  test "index filters by topic_id and preserves position order" do
    topic = Topic.create!(name: "T", slug: "topic-#{SecureRandom.hex(3)}", creator: @creator)
    a = Task.create!(title: "A", creator: @creator)
    b = Task.create!(title: "B", creator: @creator)
    c = Task.create!(title: "C", creator: @creator)
    TaskTopic.create!(task: c, topic: topic, position: 1)
    TaskTopic.create!(task: a, topic: topic, position: 2)
    TaskTopic.create!(task: b, topic: topic, position: 3)

    get "/api/v1/tasks", params: { topic_id: topic.id }, headers: @headers
    titles = JSON.parse(response.body)["data"].map { |t| t["title"] }
    assert_equal %w[C A B], titles
  end

  test "create uses agent as creator" do
    post "/api/v1/tasks", params: { title: "New task" }, headers: @headers
    assert_response :created
    data = JSON.parse(response.body)["data"]
    assert_equal @agent.id, data["creator_id"]
  end

  test "update PATCH changes fields" do
    t = Task.create!(title: "x", creator: @creator)
    patch "/api/v1/tasks/#{t.id}", params: { status: "done" }, headers: @headers
    assert_response :success
    assert t.reload.done?
  end

  test "destroy" do
    t = Task.create!(title: "x", creator: @creator)
    delete "/api/v1/tasks/#{t.id}", headers: @headers
    assert_response :no_content
  end

  test "nested POST task_topics links task to topic with auto-position" do
    t = Task.create!(title: "x", creator: @creator)
    topic = Topic.create!(name: "T", slug: "t-#{SecureRandom.hex(3)}", creator: @creator)

    post "/api/v1/tasks/#{t.id}/topics", params: { topic_id: topic.id }, headers: @headers
    assert_response :created
    data = JSON.parse(response.body)["data"]
    assert_equal t.id, data["task_id"]
    assert_equal 1, data["position"]
  end

  test "nested POST with explicit position" do
    t = Task.create!(title: "x", creator: @creator)
    topic = Topic.create!(name: "T", slug: "t-#{SecureRandom.hex(3)}", creator: @creator)

    post "/api/v1/tasks/#{t.id}/topics", params: { topic_id: topic.id, position: 42 }, headers: @headers
    assert_response :created
    assert_equal 42, JSON.parse(response.body)["data"]["position"]
  end

  test "nested DELETE unlinks" do
    t = Task.create!(title: "x", creator: @creator)
    topic = Topic.create!(name: "T", slug: "t-#{SecureRandom.hex(3)}", creator: @creator)
    TaskTopic.create!(task: t, topic: topic, position: 1)

    delete "/api/v1/tasks/#{t.id}/topics/#{topic.id}", headers: @headers
    assert_response :no_content
    refute TaskTopic.exists?(task: t, topic: topic)
  end

  test "nested operations require update on Task (not TaskTopic)" do
    t = Task.create!(title: "x", creator: @creator)
    topic = Topic.create!(name: "T", slug: "t-#{SecureRandom.hex(3)}", creator: @creator)

    read_only = AgentActor.create!(name: "ro-#{SecureRandom.hex(3)}", description: "t")
    grant(read_only, "Task", %w[read])

    post "/api/v1/tasks/#{t.id}/topics",
         params: { topic_id: topic.id },
         headers: { "Authorization" => "Bearer #{read_only.api_token}" }
    assert_response :forbidden
  end
end
