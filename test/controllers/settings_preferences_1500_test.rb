require "test_helper"

# #1500 (aus immoos uebernommen, Hans): vier Punkte an der Vorlieben-Card.
# Geprüft wird, was man sieht und was man darf — der Rest steht in
# actor_preference_defaults_test.
class SettingsPreferences1500Test < ActionDispatch::IntegrationTest
  def anmelden(**rechte)
    actor = HumanActor.create!(name: "Hans", email: "p-#{SecureRandom.hex(3)}@t.local",
                               password: "secretsecret")
    rechte.each { |rt, actions| grant(actor, rt.to_s, actions) }
    post "/login", params: { email: actor.email, password: "secretsecret" }
    actor
  end

  def card = get settings_blade_path("preferences")

  # ── Punkt 2: deutsche Namen ───────────────────────────────────────────
  test "die Kartenbreiten stehen im Klartext, der Code-Name bleibt als Titel" do
    anmelden(Actor: %w[read update], KnowledgeItem: %w[read])
    card

    assert_response :success
    assert_includes @response.body, "Aufgaben-Liste", "list:tasks im Klartext"
    assert_includes @response.body, "Wissenseintrag", "ki im Klartext"
    assert_includes @response.body, %(title="list:tasks"), "der Code-Name bleibt auffindbar"
  end

  test "eine unbekannte Kartenart faellt auf ihren Code-Namen zurueck" do
    actor = anmelden(Actor: %w[read update], KnowledgeItem: %w[read])
    actor.update_preferences("card_widths" => { "vollkommen_neue_art" => 30 })

    card

    assert_response :success
    assert_includes @response.body, "vollkommen_neue_art",
                    "der Blade-Stack erfindet Kartenarten — die Card darf daran nicht scheitern"
  end

  # ── Punkt 3: die erübrigte Einstellung ist weg ────────────────────────
  test "die Sidebar-Klick-Einstellung gibt es nicht mehr" do
    anmelden(Actor: %w[read update], KnowledgeItem: %w[read])
    card

    assert_response :success
    assert_not_includes @response.body, "sidebar_click_mode"
    assert_not Actor.new.respond_to?(:pref_sidebar_click_mode)
  end

  # ── Punkt 4: „Das bin ich" steht oben ─────────────────────────────────
  test "Das bin ich steht vor allen anderen Abschnitten" do
    anmelden(Actor: %w[read update], KnowledgeItem: %w[read])
    card

    assert_response :success
    selbst  = @response.body.index(I18n.t("preferences.self_ki_title"))
    sprache = @response.body.index(I18n.t("preferences.language_title"))
    assert selbst && sprache
    assert_operator selbst, :<, sprache, "die Selbst-Identitaet gehoert ganz nach oben"
  end

  # ── Punkt 1: der Standard für neue Nutzer ─────────────────────────────
  test "ohne Recht, Nutzer anzulegen, gibt es den Standard-Abschnitt nicht" do
    anmelden(Actor: %w[read update], KnowledgeItem: %w[read])
    card

    assert_response :success
    assert_not_includes @response.body, I18n.t("preferences.default_title")
  end

  test "wer Nutzer anlegen darf, sieht den Abschnitt und kann uebernehmen" do
    # Bewusst NICHT die Sprache setzen: Die Card folgt der Sprache des Actors —
    # mit "en" waere sie englisch, und die deutschen Erwartungen oben
    # scheiterten an etwas, das gar nicht gefragt ist.
    actor = anmelden(Actor: %w[read create update], KnowledgeItem: %w[read])
    actor.update_preferences("wheel_preset" => "fast")

    card
    assert_response :success
    assert_includes @response.body, I18n.t("preferences.default_title")
    assert_includes @response.body, I18n.t("preferences.default_none")

    post set_default_settings_preferences_path

    assert_response :redirect
    assert_equal "fast", Actor.global_defaults["wheel_preset"]
  end

  test "ohne das Recht endet die Uebernahme im 403" do
    anmelden(Actor: %w[read update], KnowledgeItem: %w[read])

    post set_default_settings_preferences_path

    assert_response :forbidden
    assert_empty Actor.global_defaults
  end

  test "der Standard laesst sich wieder entfernen" do
    actor = anmelden(Actor: %w[read create update], KnowledgeItem: %w[read])
    actor.update_preferences("wheel_preset" => "fast")
    post set_default_settings_preferences_path
    assert Actor.global_defaults?

    delete reset_default_settings_preferences_path

    assert_response :redirect
    assert_not Actor.global_defaults?
  end

  # Der Knopf nimmt den GESPEICHERTEN Stand — nicht das, was gerade im
  # Formular steht. Sonst legte man halb Getipptes für alle künftigen Nutzer
  # fest.
  test "uebernommen wird der gespeicherte Stand" do
    actor = anmelden(Actor: %w[read create update], KnowledgeItem: %w[read])
    actor.update_preferences("wheel_preset" => "fast")

    post set_default_settings_preferences_path, params: { preferences: { wheel_preset: "slow" } }

    assert_equal "fast", Actor.global_defaults["wheel_preset"]
  end
end
