module Inbox
  module Yt
    # Strukturieren + Bullet-Zusammenfassen eines Whisper-Roh-Transkripts
    # via Anthropic. Beide Pässe sind „best effort": Misserfolg führt zu
    # nil, nicht zu einer Exception — der YT-Processor toleriert das und
    # liefert das Roh-Transkript bzw. lässt die Summary weg.
    class TranscriptPostProcessor
      def initialize(actor:)
        @actor = actor
      end

      # Liefert einen strukturierten Transkript-Text (Absätze + ggf.
      # H3-Zwischenüberschriften, leichte Versprecher-Korrektur, KEINE
      # Übersetzung/Zusammenfassung). Bei < 60 % Original-Länge wird das
      # Ergebnis als "vermutlich zusammengefasst" verworfen.
      # #1410: Lange Transkripte werden in Stuecken strukturiert.
      #
      # Vorher lief der Pass immer in EINEM Aufruf mit 16.384 Ausgabe-Tokens.
      # Ein zweistuendiges Video bringt aber gut 115.000 Zeichen — die Ausgabe
      # kann gar nicht so lang werden, die 60-%-Pruefung schlaegt zwangslaeufig
      # an, und der Pass verwarf sein Ergebnis STILL. Bei Whisper fiel das nie
      # auf, weil dort der Zeitstempel-Pfad greift; ueber die Untertitel ist
      # dieser Pass der einzige, der Absaetze einzieht.
      MAX_STUECK = 24_000

      def structure(text, meta)
        stuecke = zerlegen(text, MAX_STUECK)
        teile = stuecke.each_with_index.map do |stueck, i|
          strukturiere_stueck(stueck, meta, i + 1, stuecke.size) or return nil
        end
        teile.join("\n\n").presence
      rescue => e
        Rails.logger.warn("YT structure-pass fehlgeschlagen: #{e.class} #{e.message}")
        nil
      end

      # An Satzgrenzen trennen, nicht mitten im Wort — sonst beginnt jedes
      # Stueck mit einem Bruchstueck, das die KI zu reparieren versucht.
      def zerlegen(text, max)
        return [text] if text.length <= max

        stuecke = []
        rest = text.strip
        while rest.length > max
          fenster = rest[0, max]
          schnitt = fenster.rindex(/[.!?]\s/) || fenster.rindex(" ") || max
          stuecke << rest[0, schnitt + 1].strip
          rest = rest[(schnitt + 1)..].to_s.strip
        end
        stuecke << rest if rest.present?
        stuecke
      end

      private

      def strukturiere_stueck(text, meta, nr, gesamt)
        LlmActivity.track(
          kind: :inbox_youtube_structure, actor: @actor,
          source_kind: "url", source_id: meta["webpage_url"].to_s,
          input_summary: "Strukturierung Transkript #{nr}/#{gesamt} (#{text.length} chars)",
          model: Llm::ChatClient::DEFAULT_ANTHROPIC_MODEL
        ) do |activity|
          out = Llm::ChatClient.complete(prompt: structure_prompt(text, meta),
                                         max_tokens: 16_384, activity: activity).to_s.strip
          if out.length < (text.length * 0.6)
            raise "Output zu kurz (#{out.length}/#{text.length} chars) — vermutlich Zusammenfassung statt Strukturierung"
          end
          out
        end&.presence
      end

      public

      # #660 v2 (Hans): Gliederung OHNE die Zeitstempel anzutasten. Die KI
      # bekommt die fertig nummerierten Zeitstempel-Absätze und liefert
      # NUR, vor welchem Absatz welche H3-Überschrift stehen soll —
      # `Hash{ 1-basierter Absatz-Index => "Überschrift" }`. So bleiben
      # Text und Zeitstempel deterministisch, die KI ergänzt nur die
      # Themen-Gliederung. Best effort: {} bei Misserfolg.
      def section_headings(paragraphs, meta)
        return {} if paragraphs.size < 3   # zu kurz für Gliederung
        prompt = headings_prompt(paragraphs, meta)
        out = LlmActivity.track(
          kind: :inbox_youtube_structure, actor: @actor,
          source_kind: "url", source_id: meta["webpage_url"].to_s,
          input_summary: "Gliederung (#{paragraphs.size} Absätze) für Zeitstempel-Transkript",
          model: Llm::ChatClient::DEFAULT_ANTHROPIC_MODEL
        ) do |activity|
          Llm::ChatClient.complete(prompt: prompt, max_tokens: 1_024, activity: activity).to_s
        end
        parse_headings(out, paragraphs.size)
      rescue => e
        Rails.logger.warn("YT headings-pass fehlgeschlagen: #{e.class} #{e.message}")
        {}
      end

      # Liefert eine Bullet-Zusammenfassung als Markdown-String oder nil.
      def summarize(text, meta)
        prompt = summary_prompt(text, meta)
        LlmActivity.track(
          kind: :inbox_youtube_summary, actor: @actor,
          source_kind: "url", source_id: meta["webpage_url"].to_s,
          input_summary: "Bullet-Zusammenfassung von #{text.length} chars Transkript",
          model: Llm::ChatClient::DEFAULT_ANTHROPIC_MODEL
        ) do |activity|
          out = Llm::ChatClient.complete(prompt: prompt, max_tokens: 1_024, activity: activity).to_s.strip
          raise "Leere Antwort vom Modell" if out.blank?
          out
        end
      rescue => e
        Rails.logger.warn("YT summary-pass fehlgeschlagen: #{e.class} #{e.message}")
        nil
      end

      private

      def structure_prompt(text, meta)
        <<~PROMPT
          Du bekommst ein Roh-Transkript eines YouTube-Videos (Whisper-Output).
          Es ist eine Wall of Text ohne Absätze.

          Kontext zum Video:
          - Titel: #{meta['title']}
          - Kanal: #{meta['uploader'].presence || meta['channel']}
          - Beschreibung (Auszug): #{meta['description'].to_s[0, 600]}

          Aufgabe — strukturiere den Text für gute Lesbarkeit:
          1. Sinnvolle Absätze (jeder logische Gedanke ein eigener Absatz).
          2. Bei klaren Themenwechseln eine H3-Zwischenüberschrift einfügen
             (Format: `### Thema`). Bei kurzen oder einheitlich-thematischen
             Videos KEINE Überschriften erzwingen.
          3. Versprecher, "äh"/"ähm", offensichtliche Wortwiederholungen
             leicht entfernen. Aber:
             - NICHT zusammenfassen
             - NICHT umformulieren
             - NICHT übersetzen
             - NICHT kürzen — der vollständige Inhalt muss erhalten bleiben.
          4. Sprache identisch zum Eingang.

          Antworte AUSSCHLIESSLICH mit dem strukturierten Transkript —
          keine Vorrede, keine Erklärung, keine Code-Fences.

          --- ROHTRANSKRIPT ---
          #{text}
        PROMPT
      end

      # #660 v2: nummerierte Absätze → Überschriften-Vorschläge.
      def headings_prompt(paragraphs, meta)
        numbered = paragraphs.each_with_index.map do |p, i|
          # Zeitstempel-Link für die KI uninteressant — Klartext reicht,
          # spart Tokens und verhindert Verwirrung.
          plain = p.sub(/\A\[[\d:]+\]\([^)]*\)\s*/, "")
          "#{i + 1}. #{plain[0, 400]}"
        end.join("\n\n")
        <<~PROMPT
          Du bekommst die nummerierten Absätze eines Video-Transkripts.
          Bestimme die thematische Gliederung: Vor welchen Absätzen sollte
          eine H3-Zwischenüberschrift stehen?

          Kontext:
          - Titel: #{meta['title']}
          - Kanal: #{meta['uploader'].presence || meta['channel']}

          Regeln:
          - Gib NUR Zeilen der Form `<Absatznummer>: <Überschrift>` aus,
            eine pro Themenabschnitt (also pro Abschnittsanfang).
          - Wähle nur echte Themenwechsel — typischerweise 3–8 Abschnitte,
            bei kurzen/einheitlichen Videos auch weniger oder keine.
          - Absatz 1 darf eine Überschrift bekommen, muss aber nicht.
          - Überschrift kurz (2–6 Wörter), Sprache wie das Transkript.
          - KEINE Vorrede, KEINE Erklärung, NUR die Zuordnungs-Zeilen.

          --- ABSÄTZE ---
          #{numbered}
        PROMPT
      end

      # Parst die `N: Titel`-Zeilen zu einem Hash, nur gültige Indizes.
      def parse_headings(raw, count)
        result = {}
        raw.to_s.each_line do |line|
          if (m = line.strip.match(/\A#?(\d+)[.:)\-]\s+(.+?)\s*\z/))
            idx = m[1].to_i
            title = m[2].gsub(/\A#+\s*/, "").gsub(/[*_`]/, "").strip
            result[idx] = title if idx.between?(1, count) && title.present?
          end
        end
        result
      end

      def summary_prompt(text, meta)
        <<~PROMPT
          Du bekommst ein Transkript eines YouTube-Videos. Erstelle eine
          stichpunktartige Zusammenfassung der zentralen Aussagen.

          Kontext:
          - Titel: #{meta['title']}
          - Kanal: #{meta['uploader'].presence || meta['channel']}

          Format:
          - 5–10 Markdown-Bullet-Points (einzelne Zeilen, beginnend mit `-`).
          - Jeder Punkt eine prägnante Aussage (max. 1–2 Sätze).
          - Sprache identisch zum Transkript.
          - Keine Vorrede, kein Schlusssatz, NUR die Bullet-Points.

          --- TRANSKRIPT ---
          #{text}
        PROMPT
      end
    end
  end
end
