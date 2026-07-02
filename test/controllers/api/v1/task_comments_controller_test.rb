require "test_helper"

class Api::V1::TaskCommentsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @hans = create_human
    grant(@hans, "Task", %w[read create update])

    @agent = AgentActor.create!(name: "Bot-#{SecureRandom.hex(3)}", description: "test")
    grant(@agent, "Task", %w[read create])
    # #384 Phase 3c: Beitraege werden als Reply-KIs gespeichert →
    # KnowledgeItem-create-Cap noetig (FileProxy.create gated).
    grant(@agent, "KnowledgeItem", %w[create])
    @auth = { "Authorization" => "Bearer #{@agent.api_token}" }

    @task = Task.create!(title: "Tu was", creator: @hans, status: :open)
  end

  test "POST creates comment as the calling agent" do
    # #384 Phase 3c: Beitraege landen jetzt als Reply-KIs
    # (item_type=:reply, parent_type="Task"). API-Shape bleibt
    # kompatibel.
    assert_difference -> { @task.reload.replies.count }, 1 do
      post "/api/v1/tasks/#{@task.id}/comments",
           params: { body: "ich melde mich" }, headers: @auth
    end
    assert_response :created

    body = JSON.parse(response.body)
    assert_equal "ich melde mich", body["data"]["body"]
    assert_equal @agent.id,        body["data"]["actor_id"]
    assert_equal @agent.name,      body["data"]["actor_name"]
  end

  test "POST without body returns 400 (ParameterMissing)" do
    post "/api/v1/tasks/#{@task.id}/comments", headers: @auth
    assert_response :bad_request
  end

  test "POST without create capability returns 403" do
    no_caps = AgentActor.create!(name: "No-#{SecureRandom.hex(3)}", description: "x")
    grant(no_caps, "Task", %w[read])
    post "/api/v1/tasks/#{@task.id}/comments",
         params: { body: "trotzdem" },
         headers: { "Authorization" => "Bearer #{no_caps.api_token}" }
    assert_response :forbidden
  end
end
