module Inbox
  module Yt
    # Baut den KI-Body aus den yt-dlp-Metadaten plus optionalem
    # Transkript und Bullet-Zusammenfassung. Reine Funktion (keine
    # Side-Effects, kein I/O) — entsprechend leicht testbar.
    class MarkdownBuilder
      def self.build(meta, transcript, whisper_used: false, structured: false, timestamped: false, diarized: false, summary: nil)
        parts = []
        if (kanal = meta["uploader"].presence || meta["channel"])
          parts << "**Kanal:** #{kanal}"
        end
        parts << "**Dauer:** #{format_duration(meta['duration'])}"            if meta["duration"]
        parts << "**Veröffentlicht:** #{format_date(meta['upload_date'])}"    if meta["upload_date"]
        parts << "## Zusammenfassung\n\n#{summary.strip}"                     if summary.present?
        parts << "**Beschreibung:**\n\n#{meta['description'].to_s.strip}"     if meta["description"].present?
        if transcript.present?
          parts << "#{transcript_heading(whisper_used: whisper_used, structured: structured, timestamped: timestamped, diarized: diarized)}\n\n#{transcript.strip}"
        else
          parts << "_Kein Transkript verfügbar (keine Untertitel)._"
        end
        parts.join("\n\n")
      end

      def self.format_duration(seconds)
        return "" unless seconds
        h = seconds / 3600
        m = (seconds % 3600) / 60
        s = seconds % 60
        h > 0 ? format("%d:%02d:%02d", h, m, s) : format("%d:%02d", m, s)
      end

      def self.format_date(yyyymmdd)
        return "" if yyyymmdd.blank?
        Date.parse(yyyymmdd.to_s).iso8601 rescue yyyymmdd
      end

      # Whisper-Sprach-Hint aus den yt-dlp-Metadaten. Reihenfolge:
      #   1. `language` → originale Audio-Sprache (verlässlichstes Signal)
      #   2. `original_language` → manchmal vorhanden statt language
      #   3. nil → kein Hint, Whisper macht Auto-Detect
      #
      # NICHT aus `automatic_captions` ableiten: YouTube generiert
      # auto-translate-Captions in Dutzenden Sprachen, daher landet z.B.
      # bei englischen Videos „de" ganz vorne — und Whisper macht mit
      # `language=de` aus Englisch dann eine deutsche Übersetzung.
      def self.language_hint(meta)
        lang = meta["language"].presence || meta["original_language"].presence
        return nil if lang.blank?
        lang.to_s.split("-").first.downcase
      end

      def self.transcript_heading(whisper_used:, structured:, timestamped: false, diarized: false)
        if diarized      then "## Transkript (mit Sprechererkennung, Zeitstempel)"
        elsif timestamped   then "## Transkript (Whisper, mit Zeitstempeln)"
        elsif structured then "## Transkript (Whisper, strukturiert)"
        elsif whisper_used then "## Transkript (Whisper)"
        else                    "## Transkript"
        end
      end
    end
  end
end
