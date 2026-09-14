require "test_helper"

# #1055 (Lücke aus #1052): Settings→Agenten — Token-Lebenszyklus auf
# Controller-Ebene: Einmalanzeige via Flash, kein Klartext im Blade ohne
# Flash, destroy widerruft den API-Zugang.
# #1499: Seit der Rotation nur noch benannte Token — ein neuer Agent bekommt
# gleich eines („Standard"), weitere über „Token erzeugen".
class SettingsAgentsTest < ActionDispatch::IntegrationTest
  setup do
    @hans = create_human(password: "secretsecret")
    CapabilityDefaults.grant_full!(@hans)
    post "/login", params: { email: @hans.email, password: "secretsecret" }
  end

  test "create legt Agent mit benanntem Token an und zeigt es einmalig (Flash)" do
    assert_difference "AgentActor.count", 1 do
      post "/settings/agents", params: { agent_actor: {
        name: "Test-Agent", email: "ta-#{SecureRandom.hex(3)}@test.local",
        description: "Testagent", active: true } }
    end
    agent = AgentActor.order(:id).last
    token = flash[:agent_api_token]
    assert token.present?, "Klartext-Token muss einmalig im Flash liegen"
    assert_equal agent, ApiToken.authenticate(token)&.actor
    assert_equal "Standard", flash[:agent_api_token_name]

    follow_redirect!
    assert_response :success
    assert_includes response.body, token, "Agent-Blade muss das frische Token anzeigen"
  end

  test "Agent-Blade ohne frisches Token zeigt keinen Klartext" do
    agent = create_agent
    ApiToken.issue!(actor: agent, name: "Laptop")
    get "/settings/blade/agents/sub/#{agent.id}"
    assert_response :success
    assert_includes response.body, "Laptop"
    refute_match(/\b[0-9a-f]{64}\b/, response.body)
  end

  test "issue_token stellt ein weiteres Token aus, das durch die Tür kommt" do
    agent = create_agent
    grant(agent, "Task", %w[read])
    post "/settings/agents/#{agent.id}/issue_token", params: { name: "Cron", expires_in_days: 90 }
    token = flash[:agent_api_token]
    assert token.present?

    get "/api/v1/tasks", headers: { "Authorization" => "Bearer #{token}" }
    assert_response :success
  end

  test "destroy widerruft den API-Zugang des Agenten" do
    agent = create_agent
    grant(agent, "Task", %w[read])
    token = api_token_for(agent)

    get "/api/v1/tasks", headers: { "Authorization" => "Bearer #{token}" }
    assert_response :success

    delete "/settings/agents/#{agent.id}"
    get "/api/v1/tasks", headers: { "Authorization" => "Bearer #{token}" }
    assert_response :unauthorized
  end

  test "ohne Login kein Zugriff auf Agenten-Verwaltung" do
    delete "/logout"
    agent = create_agent
    post "/settings/agents/#{agent.id}/issue_token", params: { name: "X" }
    assert_redirected_to %r{/login}
    assert_empty agent.api_tokens
  end
end
