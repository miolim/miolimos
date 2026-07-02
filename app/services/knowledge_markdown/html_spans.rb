class KnowledgeMarkdown
  # #488 (Hans, 2026-06-03): kleiner Helfer, um eine String-Transformation
  # NUR ausserhalb von <code>/<pre>-Spans auf bereits gerendertem HTML
  # laufen zu lassen. Verhindert, dass Post-Render-Resolver (References
  # `((…))`, Citations `[@…]`) Zeichen INNERHALB von Inline-Code matchen
  # und dabei ueber `</code>`-Grenzen hinweg HTML zerreissen.
  module HtmlSpans
    extend self

    CODE_OR_PRE_RE = /<(code|pre)\b[^>]*>.*?<\/\1>/mi
    # #519 (Hans, 2026-06-05): zusätzlich `<a>…</a>` aussparen — der
    # ActorMention-Resolver soll `@Name` NICHT anfassen, das bereits als
    # Anzeigetext in einem Link steckt (z.B. Personen-Wikilink
    # `<a class="wikilink-person">@Name</a>`), sonst Doppel-Verarbeitung.
    CODE_PRE_OR_LINK_RE = /<(code|pre|a)\b[^>]*>.*?<\/\1>/mi

    # Ruft den Block fuer jedes NICHT-Code-Segment auf und ersetzt es durch
    # den Rueckgabewert; Code-/Pre-Spans bleiben unveraendert.
    def outside_code(html, &block)
      apply(html, CODE_OR_PRE_RE, &block)
    end

    # Wie outside_code, spart zusätzlich Anchor-Spans (`<a>…</a>`) aus.
    def outside_code_and_links(html, &block)
      apply(html, CODE_PRE_OR_LINK_RE, &block)
    end

    def apply(html, skip_re)
      result = +""
      last   = 0
      html.scan(skip_re) do
        m = Regexp.last_match
        result << yield(html[last...m.begin(0)])
        result << m[0]
        last = m.end(0)
      end
      result << yield(html[last..].to_s)
      result
    end
  end
end
