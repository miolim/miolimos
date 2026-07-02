require "json"

module Inbox
  module Ted
    # #778 (Hans, 2026-06-29): TED-Talks tragen ihr OFFIZIELLES Transkript
    # (akkurat, mit Absätzen + Zeitstempeln) im __NEXT_DATA__-JSON der Seite.
    # Wir holen es direkt, statt das Audio erneut per Whisper zu transkribieren.
    # Reine Funktionen (kein I/O) — der Processor reicht das HTML rein.
    module Transcript
      module_function

      # Extrahiert das Next.js-Daten-JSON aus dem Seiten-HTML. nil, wenn nicht
      # gefunden / kaputt.
      def next_data(html)
        m = html.to_s.match(%r{<script id="__NEXT_DATA__"[^>]*>(.*?)</script>}m)
        return nil unless m
        JSON.parse(m[1])
      rescue JSON::ParserError
        nil
      end

      # { "video" => {…videoData…}, "paragraphs" => […translation.paragraphs…] }
      # paragraphs ist [] wenn der Talk (noch) kein Transkript hat.
      def extract(html)
        data = next_data(html)
        pp   = data&.dig("props", "pageProps") || {}
        {
          "video"      => pp["videoData"] || {},
          "paragraphs" => Array(pp.dig("transcriptData", "translation", "paragraphs"))
        }
      end

      # Baut die Markdown-Absätze: ein TED-Absatz = ein Absatz, mit
      # Zeitstempel-Link (cue-Zeit in MILLISEKUNDEN → Sekunden) auf den
      # Anfang des Absatzes. link_for: ->(start_seconds_int) { url }.
      def paragraphs_markdown(paragraphs, link_for:)
        Array(paragraphs).filter_map do |para|
          cues = Array(para["cues"])
          text = cues.map { |c| c["text"].to_s.strip }.reject(&:empty?).join(" ").gsub(/\s+/, " ").strip
          next if text.empty?
          start = (cues.first&.dig("time").to_i / 1000).floor.clamp(0, nil)
          "[#{Inbox::Yt::TimestampedTranscript.format_ts(start)}](#{link_for.call(start)}) #{text}"
        end
      end

      # Vollständiger KI-Body aus videoData + Absatz-Markdown.
      def build_markdown(video, paragraphs_md)
        parts = []
        if (sp = video["presenterDisplayName"].to_s.presence)
          parts << "**Sprecher:** #{sp}"
        end
        if (d = video["duration"].to_i) > 0
          parts << "**Dauer:** #{Inbox::Yt::MarkdownBuilder.format_duration(d)}"
        end
        if (rec = video["recordedOn"].to_s.presence)
          parts << "**Aufgenommen:** #{format_date(rec)}"
        end
        if (pub = video["publishedAt"].to_s.presence)
          parts << "**Veröffentlicht:** #{format_date(pub)}"
        end
        if (desc = video["description"].to_s.strip).present?
          parts << "**Beschreibung:**\n\n#{desc}"
        end
        if paragraphs_md.present?
          parts << "## Transkript (TED, offiziell)\n\n#{paragraphs_md.join("\n\n")}"
        else
          parts << "_Kein offizielles TED-Transkript verfügbar._"
        end
        parts.join("\n\n")
      end

      def format_date(str)
        Date.parse(str.to_s).iso8601
      rescue ArgumentError, TypeError
        str.to_s
      end
    end
  end
end
