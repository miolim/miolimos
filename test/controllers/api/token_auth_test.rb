require "test_helper"

# #1499 (Hans): „Wie lange gelten die Token und lassen sie sich einzeln
# zurueckziehen?"
#
# Hier steht die Antwort dort, wo sie zaehlt: an der Tuer. Die Regeln aus dem
# Modell nuetzen nichts, wenn die Anmeldung an der Schnittstelle sie nicht
# anwendet.
class Api::TokenAuthTest < ActionDispatch::IntegrationTest
  setup do
    @agent = AgentActor.create!(name: "Test-Agent", email: "agent-#{SecureRandom.hex(3)}@test.local",
                                description: "Testzweck", active: true)
    @agent.grant_default_capabilities!
    @alt = AgentActor.generate_api_token
    @agent.update!(api_token: @alt)
  end

  def hole(token)
    get "/api/v1/tasks", headers: { "Authorization" => "Bearer #{token}" }
  end

  test "ein benanntes Token kommt durch" do
    t = ApiToken.issue!(actor: @agent, name: "Laptop")
    hole(t.token)
    assert_response :success
  end

  test "das zurueckgezogene Token wird abgewiesen, das andere kommt weiter durch" do
    a = ApiToken.issue!(actor: @agent, name: "Laptop")
    b = ApiToken.issue!(actor: @agent, name: "Cron")
    a.revoke!

    hole(a.token)
    assert_response :unauthorized
    hole(b.token)
    assert_response :success, "der Rueckzug trifft genau eines"
  end

  test "ein abgelaufenes Token wird abgewiesen" do
    t = ApiToken.issue!(actor: @agent, name: "Kurz", expires_at: 1.minute.ago)
    hole(t.token)
    assert_response :unauthorized
  end

  test "ein Token eines inaktiven Agenten wird abgewiesen" do
    t = ApiToken.issue!(actor: @agent, name: "Laptop")
    @agent.update!(active: false)
    hole(t.token)
    assert_response :unauthorized, "der Not-Aus am Agenten wirkt auch auf benannte Token"
  end

  # Bis zur Rotation senden alle laufenden Agenten noch ihr altes Token. Ein
  # Umstieg, der sie gleichzeitig aussperrt, waere das Gegenteil von
  # Sicherheit.
  test "das alte Token an der Actor-Spalte gilt weiter" do
    hole(@alt)
    assert_response :success
  end

  test "Unsinn und leerer Kopf werden abgewiesen" do
    hole("gibtsnicht")
    assert_response :unauthorized
    get "/api/v1/tasks"
    assert_response :unauthorized
    get "/api/v1/tasks", headers: { "Authorization" => "Bearer " }
    assert_response :unauthorized
  end

  # Punkt 2: Ohne Benutzungsspur sieht man weder ein totes Token noch eines,
  # das jemand anderes benutzt.
  test "jeder Aufruf schreibt mit, wann das Token zuletzt benutzt wurde" do
    t = ApiToken.issue!(actor: @agent, name: "Laptop")
    assert_nil t.last_used_at

    hole(t.token)
    assert_response :success
    assert t.reload.last_used_at.present?, "benanntes Token"

    @agent.update_column(:api_token_last_used_at, nil)
    hole(@alt)
    assert_response :success
    assert @agent.reload.api_token_last_used_at.present?, "auch das alte Token"
  end
end
