require "test_helper"

# #1520 (Hans): „Gibt es schon die Möglichkeit, dass der Nutzer selbst sein
# Passwort anpasst?" — Nein, gab es nicht. Diese Datei prüft den Weg für den,
# der sich NICHT anmelden kann; das Ändern im angemeldeten Zustand steht in
# settings_password_test.
class PasswordResetsTest < ActionDispatch::IntegrationTest
  setup do
    # ActionMailer::Base.deliveries wird zwischen Integrationstests NICHT
    # geleert — ohne das hier liest `token_aus_mail` im vollen Lauf die Mail
    # eines fremden Tests (z.B. einen Portal-Magic-Link), der Token passt
    # nicht, und der Test meldet einen Fehler, den es nicht gibt. Einzeln
    # laufen die Tests trotzdem gruen: die Falle zeigt sich erst in der Suite.
    ActionMailer::Base.deliveries.clear
    @actor = HumanActor.create!(name: "Hans", email: "pw-#{SecureRandom.hex(3)}@t.local",
                                password: "altesgeheim")
  end

  def link_anfordern(email = @actor.email)
    perform_enqueued_jobs { post password_resets_path, params: { email: email } }
  end

  # Der Token steckt im Link der Mail — herausgezogen wird er aus dem TEXT-Teil,
  # damit der Test denselben Weg nimmt wie der Nutzer. Bewusst `decoded`: Der
  # MIME-Rumpf ist quoted-printable, dort zerlegt ein weicher Zeilenumbruch den
  # Token mitten im Wort, und der Test scheitert an seiner eigenen Kodierung.
  def token_aus_mail
    # Ausdruecklich die Mail AN DIESEN Actor — nicht einfach die letzte.
    mail = ActionMailer::Base.deliveries.reverse.find { |m| m.to.include?(@actor.email) }
    assert mail, "es muss eine Mail an #{@actor.email} geben"
    text = (mail.text_part || mail).decoded
    roh = text[%r{/password/edit\?token=([^\s"<>]+)}, 1]
    assert roh, "die Mail muss einen Link mit Token enthalten"
    # ENTSCHEIDEND: Der Token steht im Link PROZENT-KODIERT (er enthaelt je
    # nach Zufall `=`, `+` oder `/`). Ein Browser entkodiert einmal, bevor die
    # Anwendung ihn sieht — der Test muss dasselbe tun. Ohne das reicht er die
    # kodierte Form erneut durch einen URL-Helper, kodiert doppelt, und der
    # Token loest nicht auf. Weil nicht jeder Token solche Zeichen hat, war
    # das ein LAUNISCHER Fehler: mal gruen, mal rot, ohne dass sich etwas
    # geaendert hatte.
    CGI.unescape(roh)
  end

  # Der Weg muss von der Anmeldeseite aus zu finden sein — dort steht der,
  # der ihn braucht. Ein Formular, das niemand verlinkt, gibt es nicht.
  test "die Anmeldeseite verweist auf den Weg" do
    get login_path
    assert_response :success
    assert_includes @response.body, new_password_reset_path
    assert_includes @response.body, I18n.t("passwords.forgot_link")
  end

  test "der Weg von der Anforderung bis zum neuen Passwort" do
    assert_difference -> { ActionMailer::Base.deliveries.size }, 1 do
      link_anfordern
    end
    assert_redirected_to login_path

    token = token_aus_mail
    assert token, "die Mail muss einen Link mit Token enthalten"

    get edit_password_reset_path(token: token)
    assert_response :success

    patch password_reset_path, params: { token: token, password: "neuesgeheim",
                                         password_confirmation: "neuesgeheim" }
    assert_redirected_to login_path

    assert @actor.reload.authenticate("neuesgeheim"), "das neue Passwort muss gelten"
    assert_not @actor.authenticate("altesgeheim"), "das alte darf nicht mehr gelten"
  end

  # Der Kern des Verfahrens: Der Link hängt am Salz des aktuellen Passworts.
  # Ist eines gesetzt, ist jeder noch offene Link wertlos — auch der, den ein
  # Zweiter aus demselben Postfach gefischt hat.
  test "ein benutzter Link gilt kein zweites Mal" do
    link_anfordern
    token = token_aus_mail
    patch password_reset_path, params: { token: token, password: "neuesgeheim",
                                         password_confirmation: "neuesgeheim" }
    assert_redirected_to login_path

    patch password_reset_path, params: { token: token, password: "drittesgeheim",
                                         password_confirmation: "drittesgeheim" }
    assert_redirected_to new_password_reset_path
    assert @actor.reload.authenticate("neuesgeheim"), "das zweite Setzen darf nicht durchkommen"
  end

  test "ein abgelaufener Link gilt nicht mehr" do
    link_anfordern
    token = token_aus_mail

    travel HumanActor::PASSWORD_RESET_TTL + 1.minute do
      patch password_reset_path, params: { token: token, password: "neuesgeheim",
                                           password_confirmation: "neuesgeheim" }
      assert_redirected_to new_password_reset_path
    end
    assert @actor.reload.authenticate("altesgeheim"), "das alte Passwort muss stehen bleiben"
  end

  test "ein erfundener Token fuehrt nirgendwohin" do
    get edit_password_reset_path(token: "ausgedacht")
    assert_redirected_to new_password_reset_path

    patch password_reset_path, params: { token: "ausgedacht", password: "neuesgeheim",
                                         password_confirmation: "neuesgeheim" }
    assert_redirected_to new_password_reset_path
    assert @actor.reload.authenticate("altesgeheim")
  end

  # Die Seite darf kein Verzeichnis der Konten sein: Antwort und Meldung sind
  # bei unbekannter Adresse dieselben wie bei bekannter — nur die Mail bleibt
  # aus.
  test "eine unbekannte Adresse sieht genauso aus wie eine bekannte" do
    link_anfordern
    bekannt = [response.status, response.location, flash[:notice]]
    ActionMailer::Base.deliveries.clear

    assert_no_difference -> { ActionMailer::Base.deliveries.size } do
      link_anfordern("gibtesnicht-#{SecureRandom.hex(3)}@t.local")
    end
    assert_equal bekannt, [response.status, response.location, flash[:notice]]
  end

  test "ein stillgelegter Zugang bekommt keinen Link" do
    @actor.update!(active: false)
    assert_no_difference -> { ActionMailer::Base.deliveries.size } do
      link_anfordern
    end
    assert_redirected_to login_path
  end

  test "zwei ungleiche Eingaben aendern nichts" do
    link_anfordern
    token = token_aus_mail
    patch password_reset_path, params: { token: token, password: "neuesgeheim",
                                         password_confirmation: "vertippt" }
    assert_response :unprocessable_entity
    assert @actor.reload.authenticate("altesgeheim")
  end

  test "ein zu kurzes Passwort wird abgewiesen" do
    link_anfordern
    token = token_aus_mail
    patch password_reset_path, params: { token: token, password: "kurz", password_confirmation: "kurz" }
    assert_response :unprocessable_entity
    assert @actor.reload.authenticate("altesgeheim")
  end

  # Der Link setzt ein Passwort — er meldet NICHT an. Wer 2FA eingeschaltet
  # hat, soll auch danach den zweiten Faktor zeigen; eine Mail darf daran
  # nicht vorbeiführen.
  test "das Zuruecksetzen meldet niemanden an" do
    link_anfordern
    token = token_aus_mail
    patch password_reset_path, params: { token: token, password: "neuesgeheim",
                                         password_confirmation: "neuesgeheim" }
    get dashboard_path
    assert_redirected_to login_path
  end
end
