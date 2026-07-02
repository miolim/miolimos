# #325 Phase 3b (Hans, 2026-05-25): Reference-Wikilink-Resolver mit
# Roam-Style `((Title))`-Syntax. Im Unterschied zu `[[Title]]` (= aktive
# Hyperlink-Referenz mit Backlink-Tracking) ist `((Title))` eine
# Zitations-Referenz: rendert als Fussnote/Inline-Klammer mit Quell-
# Angabe.
#
# Render-Varianten (per `style:`):
#   :inline    — `(Title)` kursiv inline (Default, fuer Topic-Detail-
#                Vorschau in der KI-Liste)
#   :footnote  — `¹` Superscript inline + Footnotes-Sektion am Ende.
#                Wird im Publish-Render (WorkTreeRender) genutzt.
#
# Bei `:footnote`-Mode kann ein References::Collector mitgegeben werden;
# der akkumuliert Referenzen ueber mehrere `render`-Aufrufe (z.B. die
# vielen KI-Bodies in einem Work-Tree), sodass am Ende eine einzige
# Footnotes-Sektion entsteht. Ohne Collector wird die Footnotes-Sektion
# direkt an den HTML-String angehaengt (Per-KI-Modus).
#
# Title-Resolution geht ueber KnowledgeMarkdown::Wikilinks.lookup_target
# (gleiche Logik wie [[Title]] — Title-Match oder UUID).
class KnowledgeMarkdown
  module References
    # `((Title))` oder `((Title|Display))`. Title darf alles ausser `|`
    # `)` Newline enthalten; Display analog. Bewusst NICHT geschachtelt
    # — `(((nested)))` ist nicht erlaubt.
    REFERENCE_RE = /\(\(([^\)|\n]+)(?:\|([^\)\n]+))?\)\)/

    # Akkumulator fuer Reference-Footnotes. Wird vom Aufrufer instanziiert
    # (z.B. WorkTreeRender), durch mehrere `KnowledgeMarkdown.render`-
    # Aufrufe gereicht, und am Ende per `to_html` zur Footnotes-Sektion
    # serialisiert.
    class Collector
      Entry = Struct.new(:title, :display, :target, :index, keyword_init: true)

      def initialize
        @entries  = []     # Reihenfolge der ersten Vorkommen
        @by_title = {}     # downcased title → Entry
      end

      # Liefert `[index, first_occurrence]`. Gleicher Title (case-
      # insensitiv) → gleicher Index (= Dedupe); `first_occurrence` ist
      # true nur beim ersten Vorkommen, damit nur DORT die `fnref-N`-ID
      # gesetzt wird (Duplicate-ID-frei).
      def add(title:, display: nil, target: nil)
        key = title.to_s.downcase
        if (existing = @by_title[key])
          return [existing.index, false]
        end
        entry = Entry.new(title: title, display: display, target: target, index: @entries.size + 1)
        @entries << entry
        @by_title[key] = entry
        [entry.index, true]
      end

      def any?
        @entries.any?
      end

      def empty?
        @entries.empty?
      end

      # Footnotes-Sektion als HTML. Klassen sind Tailwind-kompatibel.
      def to_html
        return "" if @entries.empty?
        items = @entries.map do |e|
          label = if e.target
                    %(<a href="/knowledge_items/#{e.target.uuid}" class="wikilink">#{CGI.escapeHTML(e.target.title)}</a>)
                  else
                    CGI.escapeHTML(e.title)
                  end
          %(<li id="fn-#{e.index}" class="footnote-item"><a href="#fnref-#{e.index}" class="footnote-backref" aria-label="Zurueck zur Stelle">&#8617;</a> #{label}</li>)
        end
        %(<section class="footnotes border-t border-slate-300 mt-8 pt-3 text-sm text-slate-700">) +
          %(<ol class="list-decimal pl-6 space-y-1">) +
            items.join +
          %(</ol>) +
        %(</section>)
      end
    end

    module_function

    # `html` ist post-Markdown HTML. `style` :inline oder :footnote.
    # `collector` ist optional, nur bei `:footnote` relevant.
    def resolve(html, style: :inline, collector: nil)
      local_collector = collector || (style == :footnote ? Collector.new : nil)
      # #488 (Hans, 2026-06-03): NUR ausserhalb von <code>/<pre> ersetzen.
      # Sonst matcht `((…))` ein `((` das im Inline-Code steht (z.B. wenn
      # jemand ueber die `((`-Syntax schreibt) und frisst beim Suchen nach
      # dem `))` ein `</code>` mit — das brach das HTML und liess die
      # Monospace-Schrift „durchlaufen".
      out = HtmlSpans.outside_code(html) do |segment|
        segment.gsub(REFERENCE_RE) do
          title   = Regexp.last_match(1).strip
          display = Regexp.last_match(2)&.strip
          target  = Wikilinks.lookup_target(title)

          if style == :footnote
            render_footnote_marker(local_collector, title, display, target)
          else
            render_inline_paren(title, display, target)
          end
        end
      end

      # Per-KI-Modus: Footnotes direkt anhaengen, sonst macht der
      # Aufrufer (z.B. WorkTreeRender) das selbst nach allen renders.
      if style == :footnote && collector.nil? && local_collector.any?
        out + "\n" + local_collector.to_html
      else
        out
      end
    end

    # Inline-Klammer-Variante: kursiv in Klammern. Bei aufloesbarem
    # Target verlinkt, sonst nur Text.
    def render_inline_paren(title, display, target)
      label = display.presence || title
      if target
        %(<em class="reference-cite">(<a href="/knowledge_items/#{target.uuid}" class="wikilink">#{CGI.escapeHTML(label)}</a>)</em>)
      else
        %(<em class="reference-cite reference-cite--missing" title="((#{CGI.escapeHTML(title)})) — KI nicht gefunden">(#{CGI.escapeHTML(label)})</em>)
      end
    end

    # Footnote-Variante: Superscript-Marker mit Anker auf die Footnotes-
    # Sektion. Der Collector vergibt den Footnote-Index (1-basiert,
    # dedupliziert ueber Title).
    def render_footnote_marker(collector, title, display, target)
      idx, first = collector.add(title: title, display: display, target: target)
      id_attr = first ? %( id="fnref-#{idx}") : ""
      %(<sup class="reference-cite"><a href="#fn-#{idx}"#{id_attr}>#{idx}</a></sup>)
    end
  end
end
