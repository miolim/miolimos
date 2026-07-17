require "test_helper"

# #1055 (Lücke aus #1052): Settings→Agenten — Token-Lebenszyklus auf
# Controller-Ebene. Das Modell ist gedeckt (agent_actor_test), hier geht
# es um den Flow: Einmalanzeige via Flash beim Anlegen/Rotieren, kein
# Klartext im Blade ohne Flash, destroy widerruft den API-Zugang.
class SettingsAgentsTest < ActionDispatch::IntegrationTest
  setup do
    @hans = create_human(password: "secretsecret")
    CapabilityDefaults.grant_full!(@hans)
    post "/login", params: { email: @hans.email, password: "secretsecret" }
  end

  test "create legt Agent an und zeigt das Token einmalig (Flash)" do
    assert_difference "AgentActor.count", 1 do
      post "/settings/agents", params: { agent_actor: {
        name: "Test-Agent", email: "ta-#{SecureRandom.hex(3)}@test.local",
        description: "Testagent", active: true } }
    end
    agent = AgentActor.order(:id).last
    token = flash[:agent_api_token]
    assert token.present?, "Klartext-Token muss einmalig im Flash liegen"
    assert_equal Actor.digest_api_token(token), agent.api_token_digest

    follow_redirect!
    assert_response :success
    assert_includes response.body, token, "Agent-Blade muss das frische Token anzeigen"
  end

  test "Agent-Blade ohne frisches Token: Hinweis statt Klartext" do
    agent = create_agent
    get "/settings/blade/agents/sub/#{agent.id}"
    assert_response :success
    assert_includes response.body, I18n.t("settings.agents.common.token_hashed_hint")
  end

  test "regenerate_token rotiert: alter Digest ungültig, neues Token im Flash" do
    agent = create_agent
    old_digest = agent.api_token_digest
    post "/settings/agents/#{agent.id}/regenerate_token"
    token = flash[:agent_api_token]
    assert token.present?
    agent.reload
    assert_not_equal old_digest, agent.api_token_digest
    assert_equal Actor.digest_api_token(token), agent.api_token_digest
  end

  test "destroy widerruft den API-Zugang des Agenten" do
    agent = create_agent
    grant(agent, "Task", %w[read])
    token = agent.regenerate_api_token!

    get "/api/v1/tasks", headers: { "Authorization" => "Bearer #{token}" }
    assert_response :success

    delete "/settings/agents/#{agent.id}"
    get "/api/v1/tasks", headers: { "Authorization" => "Bearer #{token}" }
    assert_response :unauthorized
  end

  test "ohne Login kein Zugriff auf Agenten-Verwaltung" do
    delete "/logout"
    agent = create_agent
    post "/settings/agents/#{agent.id}/regenerate_token"
    assert_redirected_to %r{/login}
  end
end
