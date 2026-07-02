require "google/apis/calendar_v3"
require "signet/oauth_2/client"

# #573 v2: Termine zusätzlich in den Google-Kalender SCHREIBEN (Push-Spiegel,
# eine Richtung: miolimOS → Google; die DB bleibt Source of Truth, der
# ICS-Feed bleibt der Lese-Weg). Läuft über dieselbe OAuth-Credential wie
# Gmail — braucht den calendar.events-Scope (einmal neu verbinden).
# Ohne Scope: stiller No-Op (Events funktionieren in miolimOS normal).
class GcalPush
  SCOPE = "https://www.googleapis.com/auth/calendar.events".freeze

  def self.enabled?
    cred = GmailSender.credential
    cred.present? && cred.scopes.to_a.include?(SCOPE)
  end

  def self.upsert(event)
    return unless enabled?
    new.upsert(event)
  rescue => e
    Rails.logger.warn("GcalPush: upsert Event##{event.id} fehlgeschlagen: #{e.class} #{e.message}")
    nil
  end

  def self.remove(gcal_event_id)
    return if gcal_event_id.blank? || !enabled?
    new.remove(gcal_event_id)
  rescue => e
    Rails.logger.warn("GcalPush: remove #{gcal_event_id} fehlgeschlagen: #{e.class} #{e.message}")
    nil
  end

  def upsert(event)
    body = Google::Apis::CalendarV3::Event.new(
      summary:     event.title,
      description: [ event.description, (event.topic && "Projekt: #{event.topic.name}") ].compact.join("\n\n").presence,
      location:    event.location,
      start:       Google::Apis::CalendarV3::EventDateTime.new(date_time: event.starts_at.iso8601),
      end:         Google::Apis::CalendarV3::EventDateTime.new(date_time: (event.ends_at || event.starts_at + 1.hour).iso8601)
    )
    if event.gcal_event_id.present?
      service.update_event(calendar_id, event.gcal_event_id, body)
    else
      created = service.insert_event(calendar_id, body)
      event.update_column(:gcal_event_id, created.id)
    end
  end

  def remove(gcal_event_id)
    service.delete_event(calendar_id, gcal_event_id)
  rescue Google::Apis::ClientError => e
    raise unless e.message.to_s.match?(/notFound|deleted/i)
  end

  private

  # #573-Folge (Hans): Ziel-Kalender pro Credential einstellbar
  # (Settings → Konten, Feld Kalender-ID); leer = Hauptkalender.
  def calendar_id
    GmailSender.credential&.gcal_calendar_id.presence || "primary"
  end

  def service
    @service ||= begin
      cred = GmailSender.credential
      if cred.expired?
        client = signet(cred)
        client.refresh!
        cred.update!(access_token: client.access_token, expires_at: Time.at(client.expires_at.to_i))
      end
      svc = Google::Apis::CalendarV3::CalendarService.new
      svc.authorization = signet(cred)
      svc
    end
  end

  def signet(cred)
    Signet::OAuth2::Client.new(
      client_id:            ENV["GOOGLE_OAUTH_CLIENT_ID"] || Rails.application.credentials.dig(:google, :oauth_client_id),
      client_secret:        ENV["GOOGLE_OAUTH_CLIENT_SECRET"] || Rails.application.credentials.dig(:google, :oauth_client_secret),
      token_credential_uri: "https://oauth2.googleapis.com/token",
      refresh_token:        cred.refresh_token,
      access_token:         cred.access_token,
      expires_at:           cred.expires_at
    )
  end
end
