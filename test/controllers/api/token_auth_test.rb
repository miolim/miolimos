require "test_helper"

# #1499 (Hans): „Wie lange gelten die Token und lassen sie sich einzeln
# zurueckziehen?"
#
# Hier steht die Antwort dort, wo sie zaehlt: an der Tuer. Die Regeln aus dem
# Modell nuetzen nichts, wenn die Anmeldung an der Schnittstelle sie nicht
# anwendet. Seit der Rotation (14.09.2026) gibt es nur noch benannte Token.
class Api::TokenAuthTest < ActionDispatch::IntegrationTest
  setup do
    @agent = AgentActor.create!(name: "Test-Agent", email: "agent-#{SecureRandom.hex(3)}@test.local",
                                description: "Testzweck", active: true)
    @agent.grant_default_capabilities!
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

  # Punkt 1: Ein Token, das nie als benanntes ausgestellt wurde, kommt nicht
  # durch — so sind die alten, verstreuten Klartexte wertlos.
  test "ein gut geformtes, aber nie ausgestelltes Token wird abgewiesen" do
    ApiToken.issue!(actor: @agent, name: "Laptop")
    hole(SecureRandom.hex(32))
    assert_response :unauthorized
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
    assert t.reload.last_used_at.present?
  end
end
