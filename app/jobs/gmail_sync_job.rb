# #574-Folge (Hans, 2026-06-10): periodischer Gmail-Sync — bisher lief der
# kuratierte Sync NUR manuell (Settings→Konten-Button bzw. rake gmail:sync).
# Jetzt alle 15 Minuten via SolidQueue-Recurring (config/recurring.yml) über
# alle aktiven Google-Credentials. GmailSync.sync wählt selbst: ohne
# history-Baseline kuratierter Erst-Sync (Label + Allowlist ab sync_since),
# sonst inkrementell (mit Accept-Gate).
class GmailSyncJob < ApplicationJob
  def perform
    OauthCredential.where(provider: "google", active: true).find_each do |cred|
      GmailSync.sync(cred)
    rescue StandardError => e
      Rails.logger.warn "GmailSyncJob(credential=#{cred.id}): #{e.class}: #{e.message}"
    end
  end
end
