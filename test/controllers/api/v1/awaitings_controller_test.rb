require "test_helper"

class Api::V1::AwaitingsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @creator = create_human
    @agent = AgentActor.create!(name: "aw-api-#{SecureRandom.hex(3)}", description: "t")
    grant(@agent, "Awaiting", %w[read create update delete])
    grant(@agent, "Task",     %w[read create update delete])
    grant(@agent, "Topic",    %w[read])
    grant(@agent, "Contact",  %w[read])

    @headers = { "Authorization" => "Bearer #{@agent.api_token}" }
  end

  test "GET /api/v1/awaitings paginates open awaitings" do
    3.times { |i| Awaiting.create!(creator: @creator, title: "d#{i}", follow_up_at: Date.today + i + 1) }
    get "/api/v1/awaitings", headers: @headers
    body = JSON.parse(response.body)
    assert_response :ok
    assert_equal 3, body["meta"]["total"]
  end

  test "POST /api/v1/awaitings creates" do
    topic = Topic.create!(name: "T", slug: "t-#{SecureRandom.hex(3)}", creator: @creator)
    assert_difference -> { Awaiting.count }, 1 do
      post "/api/v1/awaitings",
           params: { title: "warte", follow_up_at: (Date.today + 3).iso8601,
                     topic_ids: [topic.id] },
           headers: @headers
    end
    body = JSON.parse(response.body)
    assert_equal [topic.id], body["data"]["topic_ids"]
  end

  test "POST /api/v1/awaitings/:id/resolve" do
    a = Awaiting.create!(creator: @creator, title: "x", follow_up_at: Date.today + 1)
    post "/api/v1/awaitings/#{a.id}/resolve",
         params: { resolution_note: "ok" }, headers: @headers
    assert_response :ok
    assert a.reload.resolved?
  end

  test "POST /api/v1/awaitings/:id/create_task returns task + awaiting" do
    a = Awaiting.create!(creator: @creator, title: "x", follow_up_at: Date.today + 1)
    assert_difference -> { Task.count }, 1 do
      post "/api/v1/awaitings/#{a.id}/create_task",
           params: { title: "Next" }, headers: @headers
    end
    body = JSON.parse(response.body)
    assert_equal "Next", body["data"]["task"]["title"]
    assert_equal "resolved", body["data"]["awaiting"]["status"]
  end

  test "GET /api/v1/awaitings filters by overdue" do
    past   = Awaiting.create!(creator: @creator, title: "p", follow_up_at: Date.today - 2)
    future = Awaiting.create!(creator: @creator, title: "f", follow_up_at: Date.today + 2)
    get "/api/v1/awaitings", params: { overdue: "true" }, headers: @headers
    body = JSON.parse(response.body)
    ids = body["data"].map { |x| x["id"] }
    assert_includes ids, past.id
    refute_includes ids, future.id
  end
end
