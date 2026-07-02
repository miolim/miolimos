require "google/apis/gmail_v1"
require "signet/oauth_2/client"
require "base64"

# #536 P0: Mail-VERSAND über die Gmail-API mit der bestehenden OAuth-
# Credential (Hans' Wahl: kein SMTP, kein neuer Zugangsweg — Versand läuft
# über sein Konto, Mails erscheinen dort in „Gesendet").
#
# Braucht den Scope https://www.googleapis.com/auth/gmail.send an der
# Credential — bis zur Neu-Einwilligung wirft send! einen klaren Fehler.
# Token-Refresh + Retry spiegeln GmailSync.
class GmailSender
  class Error < StandardError; end

  SEND_SCOPE = "https://www.googleapis.com/auth/gmail.send".freeze

  def self.available?
    credential.present?
  end

  # Hat die gespeicherte Credential den Send-Scope schon? (Nach Scope-
  # Erweiterung in Settings::Accounts muss Hans einmal neu verbinden.)
  def self.send_scope_granted?
    credential&.scopes&.include?(SEND_SCOPE) || false
  end

  def self.credential
    OauthCredential.active.where(provider: "google").order(:id).first
  end

  # mail: ein Mail::Message (von ActionMailer gebaut). Liefert die Gmail-
  # Message-ID. Raw-RFC822 → base64url, users.messages.send.
  def self.deliver!(mail)
    new(credential).deliver!(mail)
  end

  def initialize(credential)
    @credential = credential
    raise Error, "Keine aktive Google-Credential — Versand nicht möglich" unless @credential
  end

  def deliver!(mail)
    unless @credential.scopes.to_a.include?(SEND_SCOPE)
      raise Error, "Gmail-Send-Scope fehlt — in Einstellungen → Konten den Google-Account einmal neu verbinden"
    end
    mail.from = @credential.email_address if mail.from.blank?
    msg = Google::Apis::GmailV1::Message.new(raw: mail.to_s)
    with_retry do
      service.send_user_message("me", msg).id
    end
  end

  private

  def service
    @service ||= begin
      refresh_token_if_needed!
      svc = Google::Apis::GmailV1::GmailService.new
      svc.authorization = signet_client
      svc
    end
  end

  def signet_client
    Signet::OAuth2::Client.new(
      client_id:            google_oauth_client_id,
      client_secret:        google_oauth_client_secret,
      token_credential_uri: "https://oauth2.googleapis.com/token",
      refresh_token:        @credential.refresh_token,
      access_token:         @credential.access_token,
      expires_at:           @credential.expires_at
    )
  end

  def refresh_token_if_needed!
    return unless @credential.expired?
    client = signet_client
    client.refresh!
    @credential.update!(
      access_token: client.access_token,
      expires_at:   Time.at(client.expires_at.to_i)
    )
  end

  def with_retry(max: 1)
    attempts = 0
    begin
      yield
    rescue Google::Apis::AuthorizationError, Signet::AuthorizationError => e
      attempts += 1
      if attempts <= max
        @credential.update!(expires_at: 1.minute.ago)
        refresh_token_if_needed!
        @service = nil
        retry
      else
        raise Error, "Gmail-Auth nach Refresh fehlgeschlagen: #{e.message}"
      end
    rescue Google::Apis::Error => e
      raise Error, "Gmail-Versand fehlgeschlagen: #{e.message}"
    end
  end

  def google_oauth_client_id
    ENV["GOOGLE_OAUTH_CLIENT_ID"] || Rails.application.credentials.dig(:google, :oauth_client_id)
  end

  def google_oauth_client_secret
    ENV["GOOGLE_OAUTH_CLIENT_SECRET"] || Rails.application.credentials.dig(:google, :oauth_client_secret)
  end
end
