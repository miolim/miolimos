# #1520 (Hans): Das eigene Passwort aendern, Seite „Sicherheit".
#
# Arbeitet wie die 2FA-Selbstverwaltung IMMER auf `real_actor` — nie auf einem
# Vorschau-Actor. Sonst aenderte ein Admin in der Nutzer-Vorschau versehentlich
# sein eigenes Passwort oder, schlimmer, das des Angeschauten.
class Settings::PasswordsController < Settings::BaseController
  SECURITY_STACK = "list:settings,settings:security".freeze

  def update
    aktuell = params[:current_password].to_s
    neu     = params[:password].to_s

    # Das aktuelle Passwort ist Pflicht. Eine offen stehen gelassene Sitzung
    # soll nicht reichen, um das Konto zu uebernehmen — und der Nutzer merkt
    # so auch, wenn er an einem fremden Konto sitzt.
    return zurueck(alert: t("passwords.current_wrong")) unless real_actor.authenticate(aktuell)
    return zurueck(alert: t("passwords.mismatch")) if neu != params[:password_confirmation].to_s

    real_actor.password = neu
    if real_actor.save
      zurueck(notice: t("passwords.changed_self"))
    else
      zurueck(alert: real_actor.errors.full_messages.to_sentence)
    end
  end

  private

  # Das Passwort haengt am Actor, nicht an einer Resource der Rechtematrix:
  # Wer sich anmelden kann, darf sein eigenes aendern. Der Gate bleibt
  # trotzdem stehen (Lesen auf Actor), damit stillgelegte Zugaenge nichts
  # veraendern.
  def controller_action_to_capability = "read"

  def zurueck(**flash_args)
    redirect_to settings_path(stack: SECURITY_STACK), **flash_args
  end
end
