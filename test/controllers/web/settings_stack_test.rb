require "test_helper"

# #613: Einstellungen als Blade-Stack — Liste statt Reiter, jede Seite
# ein Blade. Smoke über ALLE Seiten (fängt Extraktions-Fehler), Legacy-
# Redirects und Stack-Restore.
class SettingsStackTest < ActionDispatch::IntegrationTest
  setup do
    @hans = create_human(password: "secretsecret")
    %w[Actor OauthCredential Team Topic TaskTemplate KiTemplate PromptTemplate
       LlmActivity KnowledgeItem Task Communication].each do |rt|
      grant(@hans, rt, %w[read create update delete])
    end
    post "/login", params: { email: @hans.email, password: "secretsecret" }
  end

  test "/settings rendert das Einstellungs-Listen-Blade" do
    get "/settings"
    assert_response :success
    assert_includes response.body, 'data-uuid="list:settings"'
    Settings::BladesController::PAGES.each_value do |spec|
      assert_includes response.body, spec[:label]
    end
  end

  test "alle Seiten-Blades rendern (Smoke über die Registry)" do
    Settings::BladesController::PAGES.each_key do |page|
      get "/settings/blade/#{page}"
      assert_response :success, "Blade #{page} kaputt"
      assert_includes response.body, %(data-uuid="settings:#{page}"), "Blade #{page} ohne Card-Wrapper"
    end
  end

  test "alle Blades öffnen mit dem Capability-Satz der alten Reiter (#613-403-Regression)" do
    # Wie Hans: KEINE TaskTemplate/KiTemplate/LlmActivity-Capabilities —
    # die alten Controller gateten diese Seiten über den Base-Fallback
    # "Actor". Die Registry muss das exakt spiegeln.
    real = create_human(name: "Realo", password: "secretsecret")
    %w[Actor OauthCredential Team Topic PromptTemplate KnowledgeItem Task Communication].each do |rt|
      grant(real, rt, %w[read create update delete])
    end
    post "/login", params: { email: real.email, password: "secretsecret" }
    Settings::BladesController::PAGES.each_key do |page|
      get "/settings/blade/#{page}"
      assert_response :success, "Blade #{page} liefert #{response.status} (Gate-Drift zur alten Reiter-Seite?)"
    end
  end

  test "unbekannte Seite ist 404" do
    get "/settings/blade/quatsch"
    assert_response :not_found
  end

  test "legacy-URLs leiten auf den Stack" do
    get "/settings/users"
    assert_redirected_to "/settings?stack=list%3Asettings%2Csettings%3Ausers"
    get "/settings/preferences"
    assert_response :redirect
    assert_includes @response.redirect_url, "settings%3Apreferences"
  end

  test "stack-restore rendert Liste + Seiten-Blade serverseitig" do
    get "/settings", params: { stack: "list:settings,settings:users" }
    assert_response :success
    assert_includes response.body, 'data-uuid="settings:users"'
    assert_includes response.body, @hans.name   # Benutzer-Tabelle ist da
  end

  test "unterseiten-blades rendern (Form, Detail) und 404en sauber (#613 St.2)" do
    get "/settings/blade/users/sub/new"
    assert_response :success
    assert_includes response.body, 'data-uuid="settingssub:users:new"'

    get "/settings/blade/users/sub/#{@hans.id}:edit"
    assert_response :success
    assert_includes response.body, @hans.email

    agent = AgentActor.create!(name: "blade-agent-#{SecureRandom.hex(3)}", description: "t")
    get "/settings/blade/agents/sub/#{agent.id}"
    assert_response :success
    assert_includes response.body, agent.name

    tpl = PromptTemplate.create!(name: "Blade Tpl", slug: "blade-tpl-#{SecureRandom.hex(3)}",
                                 prompt_text: "Tu was.", creator: @hans)
    get "/settings/blade/prompt_templates/sub/#{tpl.slug}"
    assert_response :success
    assert_includes response.body, "Tu was."

    get "/settings/blade/quatsch/sub/new"
    assert_response :not_found
  end

  test "unterseiten-restore rendert serverseitig; verschwundene Records leise raus" do
    get "/settings", params: { stack: "list:settings,settings:users,settingssub:users:#{@hans.id}:edit" }
    assert_response :success
    assert_includes response.body, %(data-uuid="settingssub:users:#{@hans.id}:edit")

    # Nicht (mehr) existenter Record: Stack rendert trotzdem (Blade fehlt leise).
    get "/settings", params: { stack: "list:settings,settingssub:users:999999:edit" }
    assert_response :success
    refute_includes response.body, "settingssub:users:999999"
  end

  test "legacy-unterseiten-URLs leiten auf den Stack (#613 St.2)" do
    get "/settings/users/new"
    assert_response :redirect
    assert_includes @response.redirect_url, "settingssub%3Ausers%3Anew"

    get "/settings/users/#{@hans.id}/edit"
    assert_includes @response.redirect_url, "%3Aedit"
  end

  test "settings/list_card liefert die Listen-Card (Restore-Fetch)" do
    get "/settings/list_card"
    assert_response :success
    assert_includes response.body, 'data-uuid="list:settings"'
  end
end
