module Inbox
  module Yt
    # #660 (Hans, 2026-06-13): Transkript-Absätze mit anklickbarem
    # Zeitstempel. Gruppiert Whisper-Segmente (mit ABSOLUTEN Start-/End-
    # Sekunden, über Chunk-Grenzen hinweg) zu Absätzen und stellt jedem
    # einen `[MM:SS](video?t=Ns)`-Link voran. Reine Funktion, kein I/O.
    module TimestampedTranscript
      # Ein Absatz endet frühestens nach MIN_PARA_SECONDS an einer
      # Satzgrenze; spätestens nach MAX_PARA_SECONDS hart (Notausstieg
      # gegen Wall-of-Text bei Sprechern ohne Punkt).
      MIN_PARA_SECONDS = 30
      MAX_PARA_SECONDS = 90
      SENTENCE_END_RE  = /[.!?…][")'\]]?\z/

      module_function

      # segments: [{ "start" => Float, "end" => Float, "text" => String }, …]
      #           (absolute Sekunden über das ganze Video)
      # link_for: ->(start_seconds_int) { "https://…watch?v=ID&t=#{n}s" }
      # Liefert Markdown (Absätze durch Leerzeile getrennt) oder "".
      def build(segments, link_for:)
        paragraphs(segments, link_for: link_for).join("\n\n")
      end

      # #660 v2: Absätze als Array — damit der Caller KI-Zwischen-
      # überschriften DAZWISCHEN einweben kann, ohne die Zeitstempel
      # anzutasten. Jeder Eintrag: "[MM:SS](link) Text …".
      def paragraphs(segments, link_for:)
        group(Array(segments)).filter_map do |para|
          text = para.map { |s| s["text"].to_s.strip }.reject(&:empty?).join(" ").gsub(/\s+/, " ").strip
          next if text.empty?
          start = para.first["start"].to_f.floor.clamp(0, nil)
          "[#{format_ts(start)}](#{link_for.call(start)}) #{text}"
        end
      end

      # #776 (Hans): Sprecher-Absätze aus AssemblyAI-Utterances. #776 v2:
      # Ein langer Sprecher-Turn wird — anhand der Wort-Zeitstempel — in
      # mehrere Absätze (30–90 s, an Satzgrenzen) mit je eigenem Zeitstempel
      # zerlegt; nur der erste Absatz eines Turns trägt das Sprecher-Label,
      # die Fortsetzungen sind stempelnde Absätze desselben Sprechers. So gibt
      # es auch bei Monologen Zwischen-Zeitstempel + genug Absätze, damit die
      # H3-Themen-Gliederung greift. Ohne Wort-Timings: Fallback = 1 Absatz.
      # utterances: [{ "speaker","start",text, "words"=>[{start,end,text}] }]
      def speaker_paragraphs(utterances, link_for:)
        Array(utterances).flat_map do |u|
          full = u["text"].to_s.strip
          next [] if full.empty?
          speaker = u["speaker"].to_s.strip.presence || "?"
          words   = Array(u["words"])
          buckets = words.any? ? group(words) : [[{ "start" => u["start"].to_f, "text" => full }]]
          buckets.each_with_index.filter_map do |bucket, i|
            text = bucket.map { |w| w["text"].to_s.strip }.reject(&:empty?).join(" ").gsub(/\s+/, " ").strip
            next if text.empty?
            start = bucket.first["start"].to_f.floor.clamp(0, nil)
            label = i.zero? ? "**Sprecher #{speaker}:** " : ""
            "[#{format_ts(start)}](#{link_for.call(start)}) #{label}#{text}"
          end
        end
      end

      # #660 v2: H3-Zwischenüberschriften zwischen die Absätze weben,
      # ohne diese (und damit die Zeitstempel) anzutasten.
      # headings: { 1-basierter Absatz-Index => "Titel" }.
      def weave(paragraphs, headings)
        headings ||= {}
        out = []
        paragraphs.each_with_index do |para, i|
          h = headings[i + 1]
          out << "### #{h}" if h.to_s.strip.present?
          out << para
        end
        out.join("\n\n")
      end

      # Gruppiert die Segment-Folge in Absatz-Buckets.
      def group(segments)
        buckets = []
        current = []
        para_start = nil
        segments.each do |seg|
          start = seg["start"].to_f
          para_start ||= start
          current << seg
          elapsed = (seg["end"] || start).to_f - para_start
          ends_sentence = seg["text"].to_s.strip.match?(SENTENCE_END_RE)
          if (elapsed >= MIN_PARA_SECONDS && ends_sentence) || elapsed >= MAX_PARA_SECONDS
            buckets << current
            current = []
            para_start = nil
          end
        end
        buckets << current unless current.empty?
        buckets
      end

      def format_ts(total_seconds)
        s = total_seconds.to_i
        h = s / 3600
        m = (s % 3600) / 60
        sec = s % 60
        h > 0 ? format("%d:%02d:%02d", h, m, sec) : format("%d:%02d", m, sec)
      end
    end
  end
end
