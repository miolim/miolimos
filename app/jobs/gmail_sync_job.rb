# #574-Folge (Hans, 2026-06-10): periodischer Gmail-Sync — bisher lief der
# kuratierte Sync NUR manuell (Settings→Konten-Button bzw. rake gmail:sync).
# Jetzt alle 15 Minuten via SolidQueue-Recurring (config/recurring.yml) über
# alle aktiven Google-Credentials. GmailSync.sync wählt selbst: ohne
# history-Baseline kuratierter Erst-Sync (Label + Allowlist ab sync_since),
# sonst inkrementell (mit Accept-Gate).
class GmailSyncJob < ApplicationJob
  def perform
    OauthCredential.where(provider: "google", active: true).find_each do |cred|
      # #1675: Das Ergebnis wurde verworfen — Fehler beim Holen einzelner Mails
      # standen nirgends. Jetzt wenigstens im Protokoll, je Konto.
      ergebnis = GmailSync.sync(cred)
      if ergebnis.respond_to?(:errors) && ergebnis.errors.to_i.positive?
        Rails.logger.warn "GmailSyncJob(credential=#{cred.id}): #{ergebnis.errors} Mail(s) nicht geholt"
      end
    rescue StandardError => e
      Rails.logger.warn "GmailSyncJob(credential=#{cred.id}): #{e.class}: #{e.message}"
    end
  end
end
