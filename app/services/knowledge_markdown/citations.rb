require "cgi"

# Pandoc-Cite-Resolver. Aus knowledge_markdown.rb (#127) ausgelagert.
#
# Syntax: `[@slug]`, `[@slug, locator]`. Zusätzlich Format-Schalter (#512,
# Hans 2026-06-04): `[@slug|y]` = nur Jahr, `[@slug|a]` = nur Autoren.
# Standard `[@slug]` = (Autor, Jahr). Schalter und Locator kombinierbar:
# `[@slug|y, S. 12]`. Slugs folgen Source.slug-Format.
class KnowledgeMarkdown
  module Citations
    # Gruppen: 1=slug, 2=mode (y|a, optional), 3=locator (optional).
    CITE_RE = /\[@([a-z0-9](?:[a-z0-9._-]*[a-z0-9])?)(?:\|([ya]))?(?:,\s*([^\]]+))?\]/

    module_function

    def resolve(html)
      return html unless html.include?("[@")
      slugs = html.scan(CITE_RE).map(&:first).uniq
      return html if slugs.empty?
      sources = Source.where(slug: slugs).index_by(&:slug)
      # #488 (Hans, 2026-06-03): nur ausserhalb von <code>/<pre> ersetzen
      # (siehe References) — `[@…]` in einem Inline-Code soll nicht aufgeloest
      # werden und kein HTML zerreissen.
      HtmlSpans.outside_code(html) do |segment|
        segment.gsub(CITE_RE) do
          slug    = Regexp.last_match(1)
          mode    = Regexp.last_match(2)
          locator = Regexp.last_match(3)&.strip
          source  = sources[slug]
          source ? rendered_hit(source, slug, locator, mode) : rendered_miss(slug, locator, mode)
        end
      end
    end

    def rendered_hit(source, slug, locator, mode = nil)
      label = format_label(source, locator, mode)
      title_attr = CGI.escapeHTML(source.title)
      slug_e     = CGI.escapeHTML(slug)
      %(<a href="/sources/#{slug_e}" class="source-cite" title="#{title_attr}" ) +
        %(data-source-slug="#{slug_e}" data-action="click->blade-stack#openSource">#{label}</a>)
    end

    def rendered_miss(slug, locator, mode = nil)
      mode_part = mode ? "|#{mode}" : ""
      tail      = locator ? ", #{CGI.escapeHTML(locator)}" : ""
      %(<span class="source-cite source-cite-broken" title="Quelle nicht gefunden">) +
        %([@#{CGI.escapeHTML(slug)}#{mode_part}#{tail}]</span>)
    end

    # #512: mode steuert die Kurzform — "y" nur Jahr, "a" nur Autoren,
    # sonst Standard (Erst-Autor, Jahr).
    def format_label(source, locator, mode = nil)
      authors = source.display_authors.presence
      year    = source.display_year
      head    = case mode
                when "y" then (year || source.title.truncate(40))
                when "a" then (authors || source.title.truncate(40))
                else
                  if authors && year
                    "#{authors.split(',').first.strip}, #{year}"
                  elsif year
                    year
                  else
                    source.title.truncate(40)
                  end
                end
      locator_part = locator.present? ? ", #{CGI.escapeHTML(locator)}" : ""
      "(#{CGI.escapeHTML(head)}#{locator_part})"
    end
  end
end
