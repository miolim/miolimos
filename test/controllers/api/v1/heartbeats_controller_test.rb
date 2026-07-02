require "test_helper"

class Api::V1::HeartbeatsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @agent = AgentActor.create!(name: "Bot-#{SecureRandom.hex(3)}", description: "test")
    grant(@agent, "Actor", %w[read update])
    grant(@agent, "Task", %w[read])
    @auth = { "Authorization" => "Bearer #{@agent.api_token}" }
  end

  test "POST stamps last_seen_at on the calling actor and returns open_tasks" do
    creator = create_human
    # #167: open_tasks zählt nur veröffentlichte Aufgaben.
    Task.create!(title: "open me", creator: creator, assignee: @agent, status: :open,
                 published_at: Time.current)
    Task.create!(title: "done one", creator: creator, assignee: @agent, status: :done,
                 published_at: Time.current)

    assert_nil @agent.reload.last_seen_at
    post "/api/v1/heartbeat", headers: @auth
    assert_response :ok

    body = JSON.parse(response.body)
    assert_equal @agent.id, body["data"]["actor_id"]
    assert_not_nil body["data"]["last_seen_at"]
    assert_equal 1, body["open_tasks"]
    assert_equal false, body["pending_trigger"]
    assert_not_nil @agent.reload.last_seen_at
  end

  test "POST returns pending_trigger=true when inbox_run_requested_at is fresh" do
    @agent.update!(inbox_run_requested_at: Time.current)

    post "/api/v1/heartbeat", headers: @auth
    body = JSON.parse(response.body)
    assert_equal true, body["pending_trigger"]
    assert_not_nil body["triggered_at"]
    # Trigger wird konsumiert.
    assert_nil @agent.reload.inbox_run_requested_at
  end

  test "POST returns pending_trigger=false when trigger is older than last seen" do
    @agent.update!(inbox_run_requested_at: 2.minutes.ago, last_seen_at: 1.minute.ago)

    post "/api/v1/heartbeat", headers: @auth
    body = JSON.parse(response.body)
    assert_equal false, body["pending_trigger"]
  end

  test "GET returns active agents with last_seen_at and age" do
    @agent.update!(last_seen_at: 30.seconds.ago)
    silent = AgentActor.create!(name: "Silent-#{SecureRandom.hex(3)}", description: "no-heartbeat")
    inactive = AgentActor.create!(
      name: "Inactive-#{SecureRandom.hex(3)}", description: "off",
      active: false, last_seen_at: Time.current
    )

    get "/api/v1/heartbeat", headers: @auth
    assert_response :ok
    body = JSON.parse(response.body)
    ids = body["data"].map { |a| a["actor_id"] }
    assert_includes ids, @agent.id
    refute_includes ids, silent.id, "agents without last_seen_at must be skipped"
    refute_includes ids, inactive.id, "inactive agents must be skipped"

    me = body["data"].find { |a| a["actor_id"] == @agent.id }
    assert me["age_seconds"].is_a?(Integer)
    assert me["age_seconds"] >= 0
  end

  test "missing token returns 401" do
    post "/api/v1/heartbeat"
    assert_response :unauthorized
  end
end
