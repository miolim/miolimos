require "application_system_test_case"

# #1498 (Hans): „Ich melde mich im Moment nur mit Nutzername und Passwort an.
# Kannst Du einmal schauen?"
#
# Der Zweitfaktor ist seit #1051 gebaut und auf Controller-Ebene geprueft.
# Was bisher fehlte: ein Test, der den WEG durch die Oberflaeche geht — vom
# Knopf in den Einstellungen bis zur naechsten Anmeldung. Genau darum ging es
# in Hans' Frage: nicht ob der Code existiert, sondern ob man ihn benutzen
# kann.
#
# Der Test rechnet den Code selbst aus dem angezeigten Geheimnis aus — wie es
# die Authenticator-App auf dem Telefon tut. Damit prueft er die ganze Kette:
# Geheimnis erzeugt, angezeigt, gespeichert, beim Anmelden wieder verlangt.
class ZweiFaktorTest < ApplicationSystemTestCase
  setup do
    @passwort = "secretsecret"
    @hans = create_human(password: @passwort)
    grant(@hans, "Actor", %w[read update])
    login_as(@hans)
  end

  def sicherheitsseite
    visit "/settings?stack=list:settings,settings:security"
    assert_selector "article.stack-card", text: /Sicherheit|Zwei/i, wait: 10
  end

  # Zuerst die Frage, die Hans eigentlich gestellt hat: Findet man es? Ein
  # Zweitfaktor, den man nur ueber die Adresszeile erreicht, ist keiner.
  test "die Sicherheits-Seite steht in der Einstellungs-Liste" do
    visit "/settings"
    assert_selector "a", text: I18n.t("settings.two_factor.title", default: "Sicherheit"), wait: 10
  rescue Minitest::Assertion
    # Der Eintrag heisst in der Liste „Sicherheit", die Ueberschrift der Seite
    # traegt den langen Namen — beide Schreibweisen zulassen.
    assert_selector "a, button", text: /Sicherheit/i, wait: 10
  end

  test "einschalten, abmelden, mit Code wieder anmelden" do
    sicherheitsseite
    refute @hans.reload.otp_enabled?, "Ausgangslage: aus"

    click_button I18n.t("settings.two_factor.enable")

    # Das Geheimnis steht als Klartext neben dem QR-Code — fuer alle, die
    # nicht scannen koennen. Genau das liest hier die „App".
    geheimnis = find("article.stack-card code", wait: 10).text.strip
    assert_match(/\A[A-Z2-7]{16,}\z/, geheimnis, "ein Base32-Geheimnis")

    fill_in "code", with: ROTP::TOTP.new(geheimnis).now
    click_button I18n.t("settings.two_factor.confirm")

    assert @hans.reload.otp_enabled?, "danach ist der Zweitfaktor an"
    assert_equal HumanActor::OTP_RECOVERY_CODE_COUNT, @hans.otp_recovery_codes.size,
                 "acht Ersatzcodes liegen bereit"
    # Sie werden GENAU EINMAL gezeigt — wer sie jetzt nicht notiert, hat sie nie.
    assert_selector "article.stack-card", text: /Ersatz|Recovery/i

    # ── Jetzt der eigentliche Beweis: die naechste Anmeldung ──────────────
    page.driver.browser.reset
    visit "/login"
    fill_in "email", with: @hans.email
    fill_in "password", with: @passwort
    click_button I18n.t("sessions.submit")

    # Passwort allein reicht nicht mehr.
    assert_current_path(/\/login\/otp/, wait: 10)

    fill_in "code", with: ROTP::TOTP.new(@hans.reload.otp_secret).now
    click_button I18n.t("sessions.otp_submit")

    assert_no_current_path(/\/login/, wait: 10)
  end

  # Ein Ersatzcode ist der Weg zurueck, wenn das Telefon weg ist. Er muss
  # funktionieren UND danach verbraucht sein — sonst ist er ein zweites
  # Passwort, das man aufgeschrieben herumliegen hat.
  test "ein Ersatzcode meldet an und ist danach verbraucht" do
    geheimnis = ROTP::Base32.random
    codes = @hans.enable_otp!(geheimnis)
    assert_equal HumanActor::OTP_RECOVERY_CODE_COUNT, codes.size

    page.driver.browser.reset
    visit "/login"
    fill_in "email", with: @hans.email
    fill_in "password", with: @passwort
    click_button I18n.t("sessions.submit")
    assert_current_path(/\/login\/otp/, wait: 10)

    fill_in "code", with: codes.first
    click_button I18n.t("sessions.otp_submit")
    assert_no_current_path(/\/login/, wait: 10)

    assert_equal codes.size - 1, @hans.reload.otp_recovery_codes.size,
                 "der benutzte Ersatzcode ist weg"
  end
end
