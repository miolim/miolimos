# Decoriert externe http(s)/mailto-Links: target=_blank, rel=noopener und
# ein kleines Ausgangs-Icon hinter dem Text. Eigene Domain
# (os.miolim.de) bleibt unangetastet, damit interne Navigation in Turbo
# bleibt. Aus knowledge_markdown.rb (#127) ausgelagert.
class KnowledgeMarkdown
  module ExternalLinks
    ICON =
      %(<svg xmlns="http://www.w3.org/2000/svg" class="inline-block w-3 h-3 ml-0.5 align-baseline opacity-60" ) +
      %(viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">) +
      %(<path d="M18 13v6a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h6"/>) +
      %(<polyline points="15 3 21 3 21 9"/>) +
      %(<line x1="10" y1="14" x2="21" y2="3"/></svg>).freeze

    # #735: eigener Host konfigurierbar (Default = bisheriger Prod-Host).
    _own_host = ENV.fetch("MIOLIMOS_HOST", "os.miolim.de")
    OWN_HOST_PREFIXES = [ "https://#{_own_host}", "http://#{_own_host}" ].freeze

    module_function

    def annotate(html)
      html.gsub(/<a\s+href="(https?:\/\/[^"]+|mailto:[^"]+)"([^>]*)>(.*?)<\/a>/m) do
        href       = Regexp.last_match(1)
        attrs_rest = Regexp.last_match(2)
        inner      = Regexp.last_match(3)

        if OWN_HOST_PREFIXES.any? { |p| href.start_with?(p) }
          %(<a href="#{href}"#{attrs_rest}>#{inner}</a>)
        else
          target_attr = ' target="_blank" rel="noopener"' unless attrs_rest.include?("target=")
          %(<a href="#{href}"#{attrs_rest}#{target_attr}>#{inner}#{ICON}</a>)
        end
      end.html_safe
    end
  end
end
