require "test_helper"

# #1675: LucideFetcher holt ein SVG vom CDN und schreibt es als ERB-Partial in
# app/views/shared/icons — also als CODE, den der Server beim nächsten Rendern
# ausführt. Vorher ungefiltert und von `@latest`: Ein `<%` im gelieferten Inhalt
# (kompromittiertes Paket, gekaperter CDN-Pfad) wäre serverseitig gelaufen.
class LucideFetcherTest < ActiveSupport::TestCase
  ECHT = <<~SVG
    <!-- @license lucide-static - ISC -->
    <svg class="lucide lucide-tag" xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24"
         fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
      <path d="M12.586 2.586A2 2 0 0 0 11.172 2H4a2 2 0 0 0-2 2v7.172a2 2 0 0 0 .586 1.414l8.704 8.704a2.426 2.426 0 0 0 3.42 0l6.58-6.58a2.426 2.426 0 0 0 0-3.42z" />
      <circle cx="7.5" cy="7.5" r=".5" fill="currentColor" />
    </svg>
  SVG

  test "ein echtes Icon kommt durch — nur Formen und Zeichen-Attribute" do
    innen = LucideFetcher.bereinige(ECHT)
    assert_includes innen, "<path"
    assert_includes innen, "<circle"
    assert_includes innen, 'cx="7.5"'
    refute_includes innen, "<svg"
    refute_includes innen, "license"
  end

  test "ERB, Skripte, Ereignis-Attribute und Fremdelemente kommen NICHT durch" do
    boese = [
      '<svg><path d="M1 1"/><%= File.read("/etc/passwd") %></svg>',
      '<svg><path d="<%= 1 %>"/></svg>',
      '<svg><script>alert(1)</script><path d="M1 1"/></svg>',
      '<svg><path d="M1 1" onclick="alert(1)"/></svg>',
      '<svg><foreignObject><body xmlns="http://www.w3.org/1999/xhtml"><img src=x onerror=alert(1)></body></foreignObject></svg>',
      '<svg><a href="javascript:alert(1)"><path d="M1 1"/></a></svg>',
      '<svg><use href="https://boese.example/x.svg#a"/></svg>'
    ]
    boese.each do |svg|
      innen = LucideFetcher.bereinige(svg)
      gefaehrlich = innen.to_s.match?(/<%|%>|script|onclick|onerror|foreignObject|href|javascript/i)
      refute gefaehrlich, "durchgekommen: #{svg} → #{innen.inspect}"
    end
  end

  test "ohne eine einzige erlaubte Form gibt es kein Icon" do
    assert_nil LucideFetcher.bereinige("<svg><script>x</script></svg>")
    assert_nil LucideFetcher.bereinige("kein svg")
  end

  test "die Quelle ist auf eine Version festgelegt, nicht auf latest" do
    refute_includes LucideFetcher::CDN_URL, "@latest"
    assert_match(/lucide-static@\d+\.\d+\.\d+/, format(LucideFetcher::CDN_URL, "tag"))
  end
end
