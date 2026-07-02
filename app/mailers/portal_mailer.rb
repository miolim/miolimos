# #536: alle Portal-Mails. Versand läuft über die Gmail-API (GmailSender);
# Absender ist Hans' verbundenes Konto (setzt GmailSender, wenn from leer).
class PortalMailer < ApplicationMailer
  # #536: Absender-Alias — wenn in den Credentials google.send_as hinterlegt
  # ist (und das Alias im Gmail-Konto als „Senden als" verifiziert wurde),
  # gehen Portal-Mails mit dieser Adresse raus; sonst mit der Konto-Adresse.
  default from: -> { PortalMailer.sender_address }

  def self.sender_address
    Rails.application.credentials.dig(:google, :send_as).presence ||
      GmailSender.credential&.email_address
  end

  # Magic-Link (Login). 15 Minuten gültig (PortalAccess::MAGIC_LINK_TTL).
  def magic_link(access)
    @access = access
    @url    = portal_consume_session_url(token: access.magic_token, host: PortalMailer.portal_host)
    # #619 Stufe 3: in der Sprache des Zugangs.
    I18n.with_locale(mail_locale(access)) do
      mail to: access.email,
        subject: t("portal.mail.magic_link_subject", project: access.topic.name)
    end
  end

  # Hans' Antwort / neue Freigaben → Ping an den Kunden.
  def update_ping(access, what:)
    @access = access
    @what   = what
    @url    = portal_root_url(host: PortalMailer.portal_host)
    I18n.with_locale(mail_locale(access)) do
      mail to: access.email,
        subject: t("portal.mail.update_ping_subject", project: access.topic.name)
    end
  end

  # Kundennachricht → interne Benachrichtigung an Hans' eigenes Postfach.
  def customer_message_internal(message, access)
    @message = message
    @access  = access
    to = GmailSender.credential&.email_address
    return if to.blank?
    mail to: to, subject: "Portal: Nachricht von #{access.email} (#{access.topic.name})"
  end

  # Host für Links in Mails — die Subdomain ist seit 2026-06-10 im
  # cloudflared-Tunnel verdrahtet (Ingress + CNAME) und der Default.
  def self.portal_host
    ENV.fetch("PORTAL_HOST", "portal.miolim.de")
  end

  private

  # #619 Stufe 3: Sprache der Kunden-Mail = Sprache des Zugangs (Fallback Default).
  def mail_locale(access)
    access.locale.presence || I18n.default_locale
  end
end
