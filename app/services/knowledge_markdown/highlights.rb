# #564: Highlight-Verarbeitung (`==text==`-Marks) — aus knowledge_markdown.rb
# extrahiert (reiner Code-Move, #314/#365/#387/#402/#450/#475/#496/#543).
class KnowledgeMarkdown
  module Highlights
    extend ActiveSupport::Concern

    # #314 (Hans, 2026-05-23): farbige Highlights ueber `==text==` (Obsidian-
    # Konvention). Default-Farbe gelb. Verarbeitet nur Text ausserhalb
    # `<pre>`/`<code>`-Bloecke — innerhalb soll der Source-Marker `==…==`
    # literal sichtbar bleiben.
    #
    # Erlaubte Syntaxen (alle case-insensitiv beim Farbnamen):
    #   ==Text==                  → gelb (Default)
    #   ==Text|rot==              → Suffix-Form
    #   ==rot|Text==              → Prefix-Form
    #   ==|rot Text==             → Prefix-Form mit fuehrendem Pipe (Hans-Variante)
    #   ==rot: Text==             → Prefix-Form mit Doppelpunkt
    # Unbekannte Farbnamen fallen auf gelb zurueck und werden als Text
    # belassen (kein silentes Verschlucken).
    HIGHLIGHT_COLORS = %w[gelb rot gruen blau lila].freeze
    # #365 Phase 3: Newline im Inhalt erlaubt; Lazy-Quantifier + 800-Zeichen-
    # Cap verhindern Runaway-Match. #387: optionaler 8-Hex-Anker + Tag-Suffix.
    # #475: Anker 8-Hex ODER 6-stellig. #543: einzelne `=` im Inner erlaubt
    # (nur `==` bleibt Delimiter) — Highlights um Links (`href="…"`) brauchen das.
    # #617 v2 (Hans): Limit 800 → 4000. Der Whole-Block-Wrapper kennt
    # KEINE Längengrenze — ein Block-Highlight auf einen langen
    # Transkript-Absatz (>800 Zeichen) erzeugte ein Highlight, das der
    # Renderer nicht mehr matchte: ==rot|… stand wörtlich im Text, die
    # Suche/Selektion in der Umgebung fand nichts mehr. 4000 deckt
    # realistische Absätze; die Grenze bleibt als ReDoS-Schutz.
    HIGHLIGHT_RE     = /==(?!\s)((?:[^=]|=(?!=)){1,4000}?)==(?:\^([a-f0-9]{8}|[a-z0-9]{6}))?((?:#[a-zA-Z0-9_-]+)*)/m.freeze
    HIGHLIGHT_PREFIX = /\A\|?(#{HIGHLIGHT_COLORS.join('|')})\s*[|:\s]\s*(.+)\z/im.freeze
    HIGHLIGHT_SUFFIX = /\A(.+?)\|(#{HIGHLIGHT_COLORS.join('|')})\z/im.freeze
    # #750 (Hans, 2026-06-21): Block- (`<pre>`) und Inline-Code (`<code>`)
    # im gerenderten HTML. Siehe mask_code_spans.
    CODE_SPAN_RE     = /<pre[^>]*>.*?<\/pre>|<code[^>]*>.*?<\/code>/m.freeze

    class_methods do
      # #402 Phase A: Count der Highlights pro Farbe im Body — fuer das
      # Filter-UI. #450: zaehlt ALLE Highlight-Syntaxen, konsistent mit
      # apply_highlights.
      def highlight_counts(body)
        counts = Hash.new(0)
        # #496: Markdown-Code (```fenced``` + `inline`) VOR dem Scan
        # ausmaskieren — sonst zaehlt ein Syntax-Beispiel im Code mit.
        strip_markdown_code(body.to_s).scan(HIGHLIGHT_RE) do |inner, _anchor, _tags|
          color, = parse_highlight_inner(inner)
          color ||= "gelb"
          counts[color] += 1 if HIGHLIGHT_COLORS.include?(color)
        end
        counts
      end

      # #496: Fenced- und Inline-Code aus dem Markdown-Source entfernen, damit
      # `==…==` darin nicht als Highlight zaehlt (konsistent mit apply_highlights).
      def strip_markdown_code(md)
        md.gsub(/```.*?```/m, " ")
          .gsub(/~~~.*?~~~/m, " ")
          .gsub(/`[^`\n]*`/, " ")
      end

      # #450: Farbe + Text aus dem Inner-Token eines `==…==`-Highlights
      # bestimmen. Geteilt von highlight_counts und apply_highlights_to.
      # nil-Farbe = Default (gelb).
      def parse_highlight_inner(inner)
        if (m = inner.match(HIGHLIGHT_PREFIX))
          [m[1].downcase, m[2]]
        elsif (m = inner.match(HIGHLIGHT_SUFFIX))
          [m[2].downcase, m[1]]
        else
          [nil, inner]
        end
      end

      # #750 (Hans, 2026-06-21): Code-Spans VOR dem Highlight-Scan durch
      # Null-Byte-Platzhalter maskieren — statt das HTML an `<pre>`/`<code>`
      # zu SPLITTEN. Beim Splitten landete ein Highlight, das Inline-Code
      # enthält (`==Text mit `code`==` → gerendert `==Text mit <code>…</code>==`),
      # mit seinen beiden `==`-Delimitern in zwei verschiedenen Chunks → kein
      # Match → der Mark fehlte in der ANSICHT (im Edit-Rohtext blieb `==…==`
      # sichtbar). Maskiert bleibt der Code ein Platzhalter im selben Chunk,
      # sodass HIGHLIGHT_RE über ihn hinweg matcht. `==…==` GANZ INNERHALB
      # eines Code-Spans bleibt literal: seine `==` stecken komplett im
      # maskierten (und damit unsichtbaren) Platzhalter-Inhalt.
      def mask_code_spans(html)
        stash = []
        masked = html.to_s.gsub(CODE_SPAN_RE) do |m|
          stash << m
          "\u0000C#{stash.size - 1}\u0000"
        end
        [masked, stash]
      end

      def unmask_code_spans(html, stash)
        return html if stash.empty?
        html.gsub(/\u0000C(\d+)\u0000/) { stash[Regexp.last_match(1).to_i] }
      end

      # #450: Highlights in bereits gerendertem HTML zu `<mark>` aufloesen —
      # fuer den Inline-Renderer (Antworten/Task-Kommentare). Ohne Backlink-
      # Indicators. Mit `filter:` wird auf die passenden Marks reduziert;
      # nil, wenn keine passende Mark vorhanden ist.
      def apply_highlights_to(html, filter: nil)
        filter = Array(filter).map(&:to_s) & HIGHLIGHT_COLORS
        # #750: Code maskieren statt splitten (siehe mask_code_spans).
        masked, stash = mask_code_spans(html)
        out = masked.gsub(HIGHLIGHT_RE) do
          inner  = Regexp.last_match(1)
          anchor = Regexp.last_match(2)
          color, text = parse_highlight_inner(inner)
          klass   = color ? "hl-#{color}" : "hl-gelb"
          id_attr = anchor ? %( id="#{anchor}") : ""
          %(<mark class="#{klass}"#{id_attr}>#{text}</mark>)
        end
        out = unmask_code_spans(out, stash)
        if filter.any?
          pattern = /<mark[^>]*class="hl-(?:#{filter.join('|')})"[^>]*>.*?<\/mark>/m
          marks = out.scan(pattern)
          return nil if marks.empty?
          out = marks.join(" ")
        end
        out
      end
    end

    # #402 Phase C: Highlight-Filter — wenn aktiv, zeigen wir NUR die
    # `<mark>`-Texte der gewaehlten Farben.
    # #675 (Hans, 2026-06-13): den (optionalen) Backlink-Indikator, der in
    # apply_highlights direkt HINTER dem `</mark>` haengt, mitnehmen —
    # sonst verschwinden die Backlinks im Filter-Modus.
    # #673 (Hans, 2026-06-13): zwischen zwei Highlights die Anzahl der
    # Woerter anzeigen, die im Original dazwischen stehen — gibt ein
    # Gefuehl fuer den raeumlichen Abstand. Sehr guenstig: laeuft nur im
    # Filter-Modus auf einer Handvoll Marks im bereits gerenderten HTML.
    def filter_highlights(html)
      colors   = @highlight_filter.join("|")
      mark_src = %(<mark[^>]*class="hl-(?:#{colors})"[^>]*>.*?</mark>) +
                 %{(?:&nbsp;<a[^>]*\\bbacklink-indicator\\b[^>]*>.*?</a>)?}
      splitter = Regexp.new("(#{mark_src})", Regexp::MULTILINE)
      # parts: [gap0, mark0, gap1, mark1, gap2, …] — ungerade = Marks,
      # gerade = Text dazwischen (gap_i liegt VOR mark_i).
      parts = html.split(splitter)
      marks = parts.values_at(*parts.each_index.select(&:odd?))
      gaps  = parts.values_at(*parts.each_index.select(&:even?))
      return %(<p class="text-slate-400 italic">— Keine Hervorhebungen in der Auswahl —</p>).html_safe if marks.empty?

      out = []
      marks.each_with_index do |m, idx|
        # #452: jede Mark in einen `.hl-filter-block`-Wrapper —
        # paragraph-actions augmentiert den (Highlight-Kontextmenue).
        out << %(<p class="hl-filter-block markdown-body py-2">#{m}</p>)
        # Luecke zwischen DIESER und der NAECHSTEN Mark = gaps[idx + 1].
        out << gap_word_label(gaps[idx + 1]) if idx < marks.size - 1
      end
      out.join.html_safe
    end

    # #673: Anzahl Woerter im (HTML-)Text zwischen zwei Highlights.
    def gap_word_label(html_fragment)
      text = CGI.unescapeHTML(html_fragment.to_s.gsub(/<[^>]+>/, " "))
      n    = text.scan(/\S+/).size
      label = "#{n} #{n == 1 ? 'Wort' : 'Wörter'} dazwischen"
      %(<div class="flex items-center gap-2 my-2 text-[11px] text-slate-400 select-none">) +
        %(<span class="flex-1 border-t border-slate-200"></span>) +
        %(<span class="italic">#{label}</span>) +
        %(<span class="flex-1 border-t border-slate-200"></span></div>)
    end

    def apply_highlights(html, backlink_data = {})
      # #750: Code-Spans maskieren statt splitten — sonst zerreißt ein
      # Inline-`<code>` ein Highlight, das es enthält (siehe mask_code_spans).
      masked, stash = self.class.mask_code_spans(html)
      out = masked.gsub(HIGHLIGHT_RE) do
        inner    = Regexp.last_match(1)
        anchor   = Regexp.last_match(2)
        if (m = inner.match(HIGHLIGHT_PREFIX))
          color = m[1].downcase
          text  = m[2]
        elsif (m = inner.match(HIGHLIGHT_SUFFIX))
          color = m[2].downcase
          text  = m[1]
        else
          color = nil
          text  = inner
        end
        klass = color ? "hl-#{color}" : "hl-gelb"
        id_attr = anchor ? %( id="#{anchor}") : ""
        # #387: Backlink-Indicator direkt am Mark statt am umgebenden
        # Block, damit mehrere Highlights pro Absatz je einen eigenen
        # Indicator zeigen.
        mark = %(<mark class="#{klass}"#{id_attr}>#{text}</mark>)
        if anchor && (sources = backlink_data[anchor]) && sources.any?
          mark + backlink_indicator_html(anchor, sources)
        else
          mark
        end
      end
      self.class.unmask_code_spans(out, stash)
    end
  end
end
