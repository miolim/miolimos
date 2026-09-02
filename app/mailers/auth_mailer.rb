# #1520 (Hans): Mails rund um den eigenen Zugang. Versand laeuft wie alle
# Mails ueber die Gmail-API (GmailSender setzt den Absender, wenn `from` leer
# bleibt) — deshalb hier kein `default from`.
class AuthMailer < ApplicationMailer
  def password_reset(actor)
    @actor = actor
    @url   = edit_password_reset_url(token: actor.generate_token_for(:password_reset))
    @minuten = (HumanActor::PASSWORD_RESET_TTL / 60).to_i
    # In der Sprache des Nutzers — die Vorliebe steht am Actor (#619).
    I18n.with_locale(actor.pref_locale.presence || I18n.default_locale) do
      mail to: actor.email, subject: t("passwords.mail.subject")
    end
  end
end
