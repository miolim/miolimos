require "test_helper"

# #1660 (Hans): „Ich hätte gern in den Einstellungen eine Gesamtübersicht,
# sowohl zeitlich als auch nach Aufgabe gegliedert und dann jeweils Modell,
# Eingabe, Ausgabe, Cache mit jeweiligen Kosten und dann Gesamtkosten."
class SettingsAgentUsageTest < ActionDispatch::IntegrationTest
  setup do
    @hans = create_human(password: "secretsecret")
    %w[Actor Task].each { |rt| grant(@hans, rt, %w[read create update]) }
    post "/login", params: { email: @hans.email, password: "secretsecret" }
  end

  def zeile!(tag: Date.current, aufgabe: "1660", model: "claude-opus-5", **werte)
    AgentUsage.create!(tag: tag, projekt: "-home-hans", aufgabe: aufgabe, model: model,
                       antworten: werte.fetch(:antworten, 3),
                       input_tokens: werte.fetch(:ein, 1_000),
                       cache_creation_tokens: werte.fetch(:cache_neu, 500_000),
                       cache_read_tokens: werte.fetch(:cache_gelesen, 4_000_000),
                       output_tokens: werte.fetch(:aus, 200_000))
  end

  test "der Bereich steht in der Einstellungs-Liste" do
    get "/settings"
    assert_response :success
    assert_includes @response.body, I18n.t("settings.pages.agent_usage")
  end

  test "die Card zeigt Gesamtsumme, Zeitverlauf, Modelle und Aufgaben" do
    zeile!
    zeile!(tag: Date.current - 2, aufgabe: "1642", model: "claude-haiku-4-5", aus: 10_000)

    get "/settings/blade/agent_usage"
    assert_response :success

    assert_includes @response.body, I18n.t("settings.agent_usage.title")
    %w[by_day by_model by_task].each do |k|
      assert_includes @response.body, I18n.t("settings.agent_usage.#{k}")
    end
    AgentUsage::ARTEN.each do |art|
      assert_includes @response.body, I18n.t("settings.agent_usage.arten.#{art}")
    end
    # Aufgabennummer als Verweis auf die Karte.
    assert_includes @response.body, %(data-blade-link-id-value="1660")
    # #1660 R1 (Hans): Die Zahl sind Modellaufrufe, nicht gepostete Antworten —
    # der Hinweis dazu muss stehen, sonst verwirrt die Größenordnung.
    assert_includes @response.body, I18n.t("settings.agent_usage.steps_note")
    assert_includes @response.body, "claude-haiku-4-5"
    # Kosten: 4 Mio Cache-Lesen (6,00) + 0,5 Mio Cache-Schreiben (15,00)
    # + 200k Ausgabe (15,00) + 1k Eingabe ≈ 36 USD für die Opus-Zeile.
    assert_match(/\$3[0-9]/, @response.body, "Gesamtkosten werden ausgewiesen")
  end

  # #1660 R2 (Hans): „Bitte bei den Aufgaben nicht nur die Nummer, sondern auch
  # den Titel mit nennen."
  test "die Aufgaben-Tabelle nennt Nummer und Titel" do
    aufgabe = Task.create!(title: "Titel-Probe für die Übersicht", creator: @hans,
                           assignee: @hans, status: :open)
    zeile!(aufgabe: aufgabe.id.to_s)

    get "/settings/blade/agent_usage"
    assert_response :success
    assert_includes @response.body, %(data-blade-link-id-value="#{aufgabe.id}")
    assert_includes @response.body, "Titel-Probe für die Übersicht"
  end

  test "eine Aufgabe im Papierkorb behaelt ihren Titel" do
    aufgabe = Task.create!(title: "Weggeworfene Aufgabe", creator: @hans,
                           assignee: @hans, status: :open)
    zeile!(aufgabe: aufgabe.id.to_s)
    aufgabe.discard!

    get "/settings/blade/agent_usage"
    assert_response :success
    assert_includes @response.body, "Weggeworfene Aufgabe"
  end

  test "der Zeitraum laesst sich umschalten" do
    zeile!(tag: Date.current - 40, aufgabe: "1500")

    get "/settings/blade/agent_usage", params: { tage: 7 }
    assert_response :success
    assert_includes @response.body, I18n.t("settings.agent_usage.no_data")

    get "/settings/blade/agent_usage", params: { tage: 90 }
    assert_response :success
    assert_includes @response.body, %(data-blade-link-id-value="1500")
  end

  test "ohne Daten steht ein Hinweis statt einer leeren Tabelle" do
    get "/settings/blade/agent_usage"
    assert_response :success
    assert_includes @response.body, I18n.t("settings.agent_usage.no_data")
  end
end
