require "test_helper"

# #1520 (Hans): das eigene Passwort ändern, Seite „Sicherheit". Der Weg für
# den, der angemeldet IST; wer sich nicht anmelden kann, steht in
# password_resets_test.
class SettingsPasswordTest < ActionDispatch::IntegrationTest
  setup do
    @actor = HumanActor.create!(name: "Hans", email: "sp-#{SecureRandom.hex(3)}@t.local",
                                password: "altesgeheim")
    grant(@actor, "Actor", %w[read update])
    grant(@actor, "KnowledgeItem", %w[read])
    post "/login", params: { email: @actor.email, password: "altesgeheim" }
  end

  def aendern(aktuell: "altesgeheim", neu: "neuesgeheim", wdh: nil)
    patch settings_password_path, params: { current_password: aktuell, password: neu,
                                            password_confirmation: wdh || neu }
  end

  test "mit dem richtigen aktuellen Passwort laesst es sich aendern" do
    aendern
    assert_redirected_to settings_path(stack: "list:settings,settings:security")
    assert @actor.reload.authenticate("neuesgeheim")
    assert_not @actor.authenticate("altesgeheim")
  end

  # Der Kern der Entscheidung: Eine offen gelassene Sitzung soll nicht
  # reichen, um das Konto zu übernehmen.
  test "ohne das aktuelle Passwort aendert sich nichts" do
    aendern(aktuell: "geraten")
    assert_equal I18n.t("passwords.current_wrong"), flash[:alert]
    assert @actor.reload.authenticate("altesgeheim"), "das alte Passwort muss stehen bleiben"
  end

  test "zwei ungleiche Eingaben aendern nichts" do
    aendern(wdh: "vertippt")
    assert_equal I18n.t("passwords.mismatch"), flash[:alert]
    assert @actor.reload.authenticate("altesgeheim")
  end

  test "ein zu kurzes Passwort wird abgewiesen" do
    aendern(neu: "kurz")
    assert flash[:alert].present?, "die Laengenregel des Modells muss durchschlagen"
    assert @actor.reload.authenticate("altesgeheim")
  end

  test "die Card zeigt das Formular" do
    get settings_blade_path("security")
    assert_response :success
    assert_includes @response.body, I18n.t("passwords.self_title")
    assert_includes @response.body, "current_password"
  end

  # Das Formular haengt an `real_actor`, nicht an `current_actor`: In der
  # Nutzer-Vorschau eines Admins darf es keinesfalls das Passwort des
  # Angeschauten setzen. Die Vorschau blockt schreibende Zugriffe ohnehin —
  # dieser Test hält beide Hälften zusammen, damit eine Lockerung der einen
  # nicht still die andere aufmacht.
  test "in der Vorschau aendert es gar nichts" do
    # Die Vorschau ist Admin-Sache und laeuft ausserdem durch den
    # Rechte-Gate (`create` auf Actor) — beides hier ausdruecklich, sonst
    # startet sie nicht und der Test prueft heimlich den Normalfall.
    @actor.update!(role: :admin)
    grant(@actor, "Actor", %w[read create update])
    anderer = HumanActor.create!(name: "Andere", email: "sp2-#{SecureRandom.hex(3)}@t.local",
                                 password: "fremdgeheim")
    post start_preview_path(anderer)
    assert_redirected_to dashboard_path, "Vorbedingung: die Vorschau muss laufen"

    aendern

    assert @actor.reload.authenticate("altesgeheim"), "das eigene Passwort bleibt"
    assert anderer.reload.authenticate("fremdgeheim"), "und das des Angeschauten erst recht"
  end

  test "ein abgemeldeter Aufruf landet auf der Anmeldung" do
    delete logout_path
    aendern
    assert_redirected_to login_path
    assert @actor.reload.authenticate("altesgeheim")
  end
end
