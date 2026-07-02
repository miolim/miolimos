namespace :communications do
  # Nach dem Add-Participants-Migration laufen lassen: liest für jede
  # Communication die Header aus raw_data und schreibt die E-Mail-Adressen
  # in die participants-Spalte. Idempotent — wer schon Daten hat, wird
  # überschrieben (harmlos, da re-parse derselben raw_data dasselbe
  # liefert).
  desc "Parses raw_data headers and backfills communications.participants"
  task backfill_participants: :environment do
    updated = 0
    skipped = 0
    Communication.includes(:oauth_credential).find_each do |comm|
      raw = comm.raw_data
      headers = raw&.dig("payload", "headers") || raw&.dig(:payload, :headers)
      if headers.blank?
        skipped += 1
        next
      end

      header_hash = headers.to_h { |h|
        name  = (h["name"]  || h[:name]).to_s.downcase
        value = (h["value"] || h[:value]).to_s
        [name, value]
      }

      participants = {
        "sender"    => parse_addrs(header_hash["from"]),
        "recipient" => parse_addrs(header_hash["to"]),
        "cc"        => parse_addrs(header_hash["cc"]),
        "bcc"       => parse_addrs(header_hash["bcc"])
      }

      comm.update_column(:participants, participants)
      updated += 1
    end
    puts "backfill_participants: updated=#{updated} skipped=#{skipped}"
  end

  def parse_addrs(header)
    return [] if header.blank?
    header.scan(/[\w.+-]+@[\w.-]+/).uniq
  end

  # Einmaliger Backfill nach der Trash-Sync-Einführung: jede
  # Communication wird mit format: "minimal" nachgelesen. Ist sie in
  # Gmail nicht mehr vorhanden (404) oder hat das TRASH-Label → lokal
  # hart löschen. Referenzen (Task/Awaiting.communication_id) werden
  # via dependent: :nullify auf NULL gesetzt.
  desc "Prune local communications that are deleted or trashed in Gmail"
  task prune_trash: :environment do
    require "google/apis/gmail_v1"
    require "signet/oauth_2/client"

    pruned = 0
    kept   = 0
    errors = 0

    OauthCredential.find_each do |cred|
      puts "— #{cred.email_address} (#{cred.communications.count} Mails)"
      sync = GmailSync.new(cred)
      client = sync.send(:gmail)

      cred.communications.find_each do |comm|
        begin
          msg = client.get_user_message("me", comm.external_id, format: "minimal")
          labels = Array(msg&.label_ids).map(&:to_s)
          if labels.include?("TRASH")
            comm.destroy!
            pruned += 1
            puts "  TRASH → #{comm.external_id} (#{comm.subject.to_s.truncate(40)})"
          else
            kept += 1
          end
        rescue Google::Apis::ClientError => e
          if e.status_code == 404
            comm.destroy!
            pruned += 1
            puts "  404   → #{comm.external_id} (#{comm.subject.to_s.truncate(40)})"
          else
            errors += 1
            puts "  ERR   → #{comm.external_id}: #{e.message}"
          end
        end
      end
    end

    puts "prune_trash: pruned=#{pruned} kept=#{kept} errors=#{errors}"
  end

  # Phase 6a — Retro-Klassifikation: alle Mails ohne Topic-Zuordnung
  # durch den Suggester jagen. Idempotent: re-run wird Mails, die beim
  # letzten Lauf als :suggest markiert wurden aber noch nicht entschieden
  # sind, erneut klassifizieren (Topic-Embeddings oder Schwellwerte
  # könnten sich geändert haben).
  desc "Run topic classifier over communications without a topic"
  task classify_all: :environment do
    suggester = Classifiers::EmailTopicSuggester.new
    unless suggester.send(:instance_variable_get, :@embedder).available?
      puts "Ollama nicht erreichbar unter http://localhost:11434 — Abbruch."
      puts "Setup: curl -fsSL https://ollama.com/install.sh | sh && ollama pull bge-m3"
      next
    end

    stats = Hash.new(0)
    mails = Communication.left_joins(:communication_topics)
                          .where(communication_topics: { id: nil })

    total = mails.count
    puts "Klassifiziere #{total} Mails ohne Thema …"

    mails.find_each.with_index(1) do |mail, i|
      result = suggester.apply(mail)
      stats[result[:decision]] += 1
      if (i % 10).zero?
        puts "  #{i}/#{total}  auto=#{stats[:auto_assign]}  suggest=#{stats[:suggest]}  skip=#{stats[:skip]}"
      end
    end

    puts "Fertig. auto=#{stats[:auto_assign]}  suggest=#{stats[:suggest]}  skip=#{stats[:skip]}"
  end
end
