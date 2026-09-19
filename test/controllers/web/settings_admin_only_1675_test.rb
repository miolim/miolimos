require "test_helper"

# #1675 (Fund 1 der Testabdeckungs-Durchsicht): Einstellungen → Benutzer und
# → Agenten prüften nur das Recht „Actor" — das hat laut Rechtematrix jeder
# Mensch. Ein Mitglied konnte so
#   (a) für jeden Agenten ein API-Token ausstellen (Agenten sehen alles — die
#       ganze Sichtbarkeit aus #602 war damit umgangen),
#   (b) die E-Mail eines Admins auf die eigene ändern und per „Passwort
#       vergessen" dessen Konto übernehmen (#1520 schloss nur die Passwort-Tür),
#   (c) andere Nutzer anlegen, sperren und löschen.
# Hans' Entscheidung (19.09.2026): beide Bereiche nur für Admins; das eigene
# Profil bleibt für jeden.
class SettingsAdminOnly1675Test < ActionDispatch::IntegrationTest
  setup do
    @hans  = create_human(name: "Hans Admin", password: "secretsecret")
    @mia   = create_human(name: "Mia Member", role: :member, password: "secretsecret")
    @gast  = create_human(name: "Gero Gast",  role: :guest,  password: "secretsecret")
    [@hans, @mia, @gast].each { |u| CapabilityDefaults.grant_full!(u) }
    @agent = create_agent
  end

  def login!(user)
    post "/login", params: { email: user.email, password: "secretsecret" }
    assert_response :redirect
  end

  # ── Agenten ─────────────────────────────────────────────────────────────

  test "Mitglied und Gast stellen kein Agenten-Token aus" do
    [@mia, @gast].each do |wer|
      login!(wer)
      assert_no_difference -> { ApiToken.count }, "#{wer.name} hat ein Token ausgestellt" do
        post "/settings/agents/#{@agent.id}/issue_token", params: { name: "Hintertür" }
      end
      assert_response :forbidden
      assert_nil flash[:agent_api_token]
      delete "/logout"
    end
  end

  test "Mitglied legt keinen Agenten an, aendert und loescht keinen, zieht kein Token zurueck" do
    token = ApiToken.issue!(actor: @agent, name: "Laptop")
    login!(@mia)

    assert_no_difference -> { AgentActor.count } do
      post "/settings/agents", params: { agent_actor: { name: "Spion", description: "x", active: true } }
    end
    assert_response :forbidden

    patch "/settings/agents/#{@agent.id}", params: { agent_actor: { name: "Umbenannt" } }
    assert_response :forbidden
    refute_equal "Umbenannt", @agent.reload.name

    post "/settings/agents/#{@agent.id}/revoke_token", params: { token_id: token.id }
    assert_response :forbidden
    assert_nil token.reload.revoked_at

    delete "/settings/agents/#{@agent.id}"
    assert_response :forbidden
    assert AgentActor.exists?(@agent.id)
  end

  test "Mitglied sieht die Agenten-Seite nicht — weder als Card noch in der Liste" do
    login!(@mia)
    get "/settings/blade/agents"
    assert_response :forbidden
    get "/settings/blade/agents/sub/#{@agent.id}"
    assert_response :forbidden

    get "/settings/list_card"
    assert_response :success
    refute_includes response.body, 'data-blade-link-id-value="agents"'
    assert_includes response.body, 'data-blade-link-id-value="preferences"', "Eigenes bleibt erreichbar"
  end

  # ── Benutzer ────────────────────────────────────────────────────────────

  test "Mitglied aendert weder E-Mail noch Namen noch Aktiv-Status eines anderen" do
    login!(@mia)
    alt = @hans.email
    patch "/settings/users/#{@hans.id}", params: {
      human_actor: { name: "Gekapert", email: "mia-uebernahme@test.local", active: "0", password: "" } }
    assert_response :forbidden
    @hans.reload
    assert_equal alt, @hans.email, "über die E-Mail liefe die Konto-Übernahme per Passwort-Reset"
    assert_equal "Hans Admin", @hans.name
    assert @hans.active?
  end

  test "Mitglied legt keine Nutzer an und loescht keine" do
    login!(@mia)
    assert_no_difference -> { HumanActor.count } do
      post "/settings/users", params: { human_actor: {
        name: "Strohmann", email: "stroh-#{SecureRandom.hex(3)}@test.local", password: "secretsecret" } }
    end
    assert_response :forbidden

    assert_no_difference -> { HumanActor.count } do
      delete "/settings/users/#{@gast.id}"
    end
    assert_response :forbidden
  end

  test "das eigene Profil bleibt: Name, E-Mail und Passwort — aber nicht Rolle und Aktiv-Status" do
    login!(@mia)
    patch "/settings/users/#{@mia.id}", params: {
      human_actor: { name: "Mia Neu", email: @mia.email, password: "", role: "admin", active: "0" } }
    assert_response :redirect
    @mia.reload
    assert_equal "Mia Neu", @mia.name
    assert @mia.member?, "die Rolle vergibt nur ein Admin"
    assert @mia.active?, "sich selbst sperren ist kein Profil-Feld"
  end

  test "Mitglied sieht in der Benutzer-Card nur sich selbst, ohne Anlegen-Knopf" do
    login!(@mia)
    get "/settings/blade/users"
    assert_response :success
    assert_includes response.body, @mia.email
    refute_includes response.body, @hans.email
    refute_includes response.body, "users:new"

    get "/settings/blade/users/sub/#{@hans.id}:edit"
    assert_response :forbidden
    get "/settings/blade/users/sub/#{@mia.id}:edit"
    assert_response :success
  end

  # ── Admin: unverändert ──────────────────────────────────────────────────

  test "Admin verwaltet weiter Nutzer und Agenten" do
    login!(@hans)
    assert_difference -> { ApiToken.count }, 1 do
      post "/settings/agents/#{@agent.id}/issue_token", params: { name: "Neu" }
    end
    patch "/settings/users/#{@mia.id}", params: {
      human_actor: { name: "Mia Umbenannt", email: @mia.email, password: "" } }
    assert_equal "Mia Umbenannt", @mia.reload.name

    get "/settings/blade/users"
    assert_includes response.body, @mia.email
    assert_includes response.body, "users:new"
    get "/settings/list_card"
    assert_includes response.body, 'data-blade-link-id-value="agents"'
  end
end
