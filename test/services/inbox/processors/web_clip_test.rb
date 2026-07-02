require "test_helper"

# #203: Coverage fuer den Web-Clipper. Pure-Function-Pfade direkt,
# Source-Upsert mit gestubbtem fetch_html via process!.
class Inbox::Processors::WebClipTest < ActiveSupport::TestCase
  setup do
    @hans = create_human
    grant(@hans, "KnowledgeItem", %w[read create update delete])
    grant(@hans, "Source",        %w[read create update delete])
    @proc = Inbox::Processors::WebClip.new
  end

  test "applies? true fuer web_url, false fuer YouTube" do
    web = InboxItem.create!(creator: @hans, source_kind: "web_url",
                             source_url: "https://example.com", status: "pending")
    yt = InboxItem.create!(creator: @hans, source_kind: "web_url",
                            source_url: "https://youtube.com/watch?v=abc", status: "pending")
    assert Inbox::Processors::WebClip.applies?(web)
    refute Inbox::Processors::WebClip.applies?(yt)
  end

  test "build_slug nutzt Host und Title-Parameterize" do
    s = @proc.send(:build_slug, "https://www.example.com/some-page", "Mein Titel hier")
    assert_includes s, "example-com"
    assert_includes s, "mein-titel"
  end

  test "build_slug ohne URL und ohne Title liefert nil" do
    assert_nil @proc.send(:build_slug, "garbage", "")
  end

  test "extract_title liefert decoded title" do
    html = "<html><head><title>Hallo &amp; Welt</title></head></html>"
    assert_equal "Hallo & Welt", @proc.send(:extract_title, html)
  end

  test "extract_title bei fehlendem Title leer" do
    assert_equal "", @proc.send(:extract_title, "<html></html>")
  end

  test "extract_meta_tags pickt OpenGraph zuerst, dann meta-name" do
    html = <<~HTML
      <html lang="de-DE">
        <meta property="og:title" content="OG-Title" />
        <meta name="author" content="Jane Doe" />
        <meta property="og:description" content="Eine Zusammenfassung" />
        <meta property="og:site_name" content="Example Times" />
        <meta property="article:published_time" content="2024-06-01T10:00:00Z" />
      </html>
    HTML
    meta = @proc.send(:extract_meta_tags, html)
    assert_equal "OG-Title",              meta[:title]
    assert_equal "Jane Doe",              meta[:author]
    assert_equal "Eine Zusammenfassung",  meta[:description]
    assert_equal "Example Times",         meta[:site_name]
    assert_equal "2024-06-01T10:00:00Z",  meta[:published]
    assert_equal "de-de",                 meta[:language]
  end

  test "extract_meta_tags ohne passende Tags liefert nils" do
    meta = @proc.send(:extract_meta_tags, "<html></html>")
    assert_nil meta[:title]
    assert_nil meta[:author]
  end

  test "parse_iso_date akzeptiert ISO + Year-only, sonst nil" do
    assert_equal Date.new(2024, 6, 1), @proc.send(:parse_iso_date, "2024-06-01T10:00:00Z")
    assert_nil @proc.send(:parse_iso_date, "")
    assert_nil @proc.send(:parse_iso_date, "garbage")
  end

  test "extract_body strippt script/style und blocked tags zu Newlines" do
    html = <<~HTML
      <html><body>
        <script>alert('x')</script>
        <style>.x{}</style>
        <p>Hallo Welt</p>
        <p>Zweiter Absatz</p>
      </body></html>
    HTML
    body = @proc.send(:extract_body, html)
    refute_includes body, "alert"
    refute_includes body, ".x{}"
    assert_includes body, "Hallo Welt"
    assert_includes body, "Zweiter Absatz"
  end

  # #693 (Hans): Boilerplate (nav/footer) raus, Hauptinhalt (<article>)
  # bevorzugt — statt der ganzen Seite.
  test "extract_body entfernt nav/footer und bevorzugt den Artikel-Inhalt" do
    html = <<~HTML
      <html><body>
        <nav>Startseite Politik Wirtschaft Abo kündigen</nav>
        <header>Seitenkopf-Logo Suche</header>
        <article>
          <h1>Der Titel</h1>
          <p>Erster echter Absatz mit Inhalt.</p>
          <p>Zweiter echter Absatz mit Inhalt.</p>
        </article>
        <aside>Auch interessant: Weitere Artikel</aside>
        <footer>AGB Datenschutz Cookies &amp; Tracking</footer>
      </body></html>
    HTML
    body = @proc.send(:extract_body, html)
    assert_includes body, "Erster echter Absatz mit Inhalt."
    assert_includes body, "Der Titel"
    refute_includes body, "Abo kündigen"        # nav
    refute_includes body, "AGB"                 # footer
    refute_includes body, "Auch interessant"    # aside
  end

  # #736 (Hans): Interview-Fragen als block-eigenstaendige <strong> (FAZ)
  # bleiben erhalten und sind mit den Antwort-<p> verzahnt; Inline-Fett
  # im Absatz wird NICHT doppelt aufgenommen.
  test "extract_body bewahrt standalone <strong> Interview-Fragen, ohne Inline-Fett zu doppeln" do
    html = <<~HTML
      <html><body>
        <article>
          <p>Eine Antwort mit <strong>betontem</strong> Wort im Absatz.</p>
          <strong>Warum ist das so?</strong>
          <p>Weil es den Kreis schließt.</p>
          <strong>Frage: Was meinen Sie damit?</strong>
          <p>Die zweite Antwort folgt hier.</p>
        </article>
      </body></html>
    HTML
    body = @proc.send(:extract_body, html)
    # Fragen (standalone strong) sind drin
    assert_includes body, "Warum ist das so?"
    assert_includes body, "Frage: Was meinen Sie damit?"
    # Antworten ebenfalls
    assert_includes body, "Weil es den Kreis schließt."
    # Reihenfolge: Frage steht vor ihrer Antwort
    assert body.index("Warum ist das so?") < body.index("Weil es den Kreis schließt."),
           "Frage muss vor der Antwort stehen"
    # Inline-<strong> im Absatz wird nicht als eigene Zeile dupliziert
    assert_equal 1, body.scan("betontem").size, "Inline-Fett darf nicht doppelt erscheinen"
  end

  # #758 (Hans, 2026-06-22): Auszeichnungen aus der Webseite als Markdown
  # ins Transkript übernehmen — Überschriften, Fett/Kursiv, Listen, Zitate,
  # Links (absolut gemacht).
  test "extract_body übernimmt Auszeichnungen als Markdown" do
    html = <<~HTML
      <html><body><article>
        <h1>Die Hauptüberschrift</h1>
        <p>Absatz mit <strong>fettem</strong> und <em>kursivem</em> Text und <a href="/relativ">Link</a>.</p>
        <h2>Zwischenüberschrift</h2>
        <ul><li>Erster Punkt</li><li>Zweiter <b>wichtiger</b> Punkt</li></ul>
        <blockquote>Ein Zitat.</blockquote>
      </article></body></html>
    HTML
    body = @proc.send(:extract_body, html, "https://example.com/artikel")
    assert_includes body, "# Die Hauptüberschrift"
    assert_includes body, "## Zwischenüberschrift"
    assert_includes body, "**fettem**"
    assert_includes body, "*kursivem*"
    assert_includes body, "[Link](https://example.com/relativ)"   # relativer Link absolut gemacht
    assert_includes body, "- Erster Punkt"
    assert_includes body, "- Zweiter **wichtiger** Punkt"
    assert_includes body, "> Ein Zitat."
    # Kein ungültiges Markdown mit Leerzeichen direkt an den Markern.
    refute_includes body, "** fettem **"
  end

  # #693 (Hans): Mehrseitige Artikel — Komplettansicht/Pagination.
  test "single_page_url findet Komplettansicht und erbt freebie-Query" do
    html = <<~HTML
      <html><body><article><p>x</p></article>
        <a href="https://www.zeit.de/a/b/komplettansicht#print">Auf einer Seite lesen</a>
      </body></html>
    HTML
    doc = Nokogiri::HTML(html)
    url = "https://www.zeit.de/a/b?freebie=tok123"
    assert_equal "https://www.zeit.de/a/b/komplettansicht?freebie=tok123",
                 @proc.send(:single_page_url, doc, url)
  end

  test "pagination_urls sammelt seite-N dedupliziert und erbt Query" do
    html = <<~HTML
      <html><body>
        <a href="/a/b/seite-2">2</a>
        <a href="/a/b/seite-3">3</a>
        <a href="/a/b/seite-2">2 nochmal</a>
        <a href="/a/b">zurueck</a>
      </body></html>
    HTML
    doc  = Nokogiri::HTML(html)
    urls = @proc.send(:pagination_urls, doc, "https://www.zeit.de/a/b?freebie=t")
    assert_equal ["https://www.zeit.de/a/b/seite-2?freebie=t",
                  "https://www.zeit.de/a/b/seite-3?freebie=t"], urls
  end

  test "extract_article bevorzugt Komplettansicht-Volltext gegenueber Seite 1" do
    page1 = <<~HTML
      <html><body><article><p>Nur der erste Absatz.</p></article>
        <a href="/a/b/komplettansicht">Auf einer Seite lesen</a>
      </body></html>
    HTML
    full = <<~HTML
      <html><body><article>
        <p>Absatz eins voll.</p><p>Absatz zwei voll.</p><p>Absatz drei voll.</p>
      </article></body></html>
    HTML
    url = "https://www.zeit.de/a/b?freebie=t"
    @proc.define_singleton_method(:fetch_html) do |u, **|
      u.include?("komplettansicht") ? full : page1
    end
    body = @proc.send(:extract_article, url, page1)
    assert_includes body, "Absatz drei voll."
    refute_includes body, "Nur der erste Absatz."
  end

  test "extract_body entfernt Z+/Freebie-Schenk-Banner" do
    html = <<~HTML
      <html><body><article>
        <p>Schenken Sie diesen Z+ Artikel jemandem ohne Abo. Diesen Monat koennen Sie noch 3/5 Artikeln verschenken.</p>
        <p>Echter Artikelinhalt hier.</p>
      </article></body></html>
    HTML
    body = @proc.send(:extract_body, html)
    assert_includes body, "Echter Artikelinhalt hier."
    refute_includes body, "Schenken Sie diesen"
  end

  test "decode_entities entwickelt nummerische und HTML-Entities" do
    assert_equal "A & B \"C\"", @proc.send(:decode_entities, "A &amp; B &quot;C&quot;")
    assert_equal "ä",            @proc.send(:decode_entities, "&#228;")
  end

  test "upsert_source legt webpage-Source an und verknuepft Author als Person-KI" do
    src = @proc.upsert_source(
      "https://example.com/article",
      "Mein Article",
      { author: "Jane Doe", site_name: "Example", description: "Abstract",
        published: "2024-06-01", language: "de" },
      actor: @hans
    )
    assert src
    assert_equal "webpage", src.csl_type
    assert_equal "Jane Doe", src.publisher
    assert_equal "Example", src.container_title
    assert_equal "https://example.com/article", src.url
    # source_creators-Row mit role=author auf Person-KI
    sc = src.source_creators.first
    assert_equal "author", sc.role
    ki = sc.knowledge_item
    assert ki.person?
    assert_equal "Jane Doe", ki.title
  end

  test "upsert_source ist idempotent ueber slug" do
    meta = { author: "X" }
    s1 = @proc.upsert_source("https://e.de/a", "Mein A", meta, actor: @hans)
    s2 = @proc.upsert_source("https://e.de/a", "Mein A", meta, actor: @hans)
    assert_equal s1.id, s2.id
  end

  test "upsert_source ohne brauchbaren slug liefert nil" do
    assert_nil @proc.upsert_source("garbage", "", {}, actor: @hans)
  end
end
