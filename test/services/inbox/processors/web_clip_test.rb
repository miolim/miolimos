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

  # ── #1462: relative Weiterleitungen ─────────────────────────────────────
  #
  # Hans: „Fehler ArgumentError: not an HTTP URI. HTTPS Seiten sollten auch
  # importiert werden koennen." — Mit HTTPS hatte es nichts zu tun. Die FAZ
  # antwortet auf ihre Kurzlinks mit 301 und einem RELATIVEN `Location`
  # (`/aktuell/feuilleton/…`). Das ist nach RFC 7231 erlaubt; `URI.parse`
  # macht daraus ein URI::Generic ohne Host, und Net::HTTP lehnte das mit
  # einer Meldung ab, die nach einem Protokoll-Problem klang.
  #
  # Geprueft wird gegen einen echten kleinen Server — die Weiterleitung ist
  # genau das, was hier schiefging, und die soll wirklich stattfinden.
  def mit_server(&block)
    require "webrick"
    server = WEBrick::HTTPServer.new(Port: 0, Logger: WEBrick::Log.new(File::NULL),
                                     AccessLog: [])
    server.mount_proc("/kurz") do |_req, res|
      res.status = 301
      res["Location"] = "/lang/artikel.html?x=1"   # RELATIV, wie bei der FAZ
    end
    server.mount_proc("/lang/artikel.html") do |_req, res|
      res.status = 200
      res["Content-Type"] = "text/html"
      res.body = "<html><head><title>Angekommen</title></head><body><p>Text</p></body></html>"
    end
    server.mount_proc("/woanders") do |_req, res|
      res.status = 302
      res["Location"] = "mailto:jemand@example.org"
    end
    server.mount_proc("/ohne-ziel") do |_req, res|
      res.status = 302
    end
    thread = Thread.new { server.start }
    yield "http://127.0.0.1:#{server.config[:Port]}"
  ensure
    server&.shutdown
    thread&.join(2)
  end

  test "relative Weiterleitung wird gegen die aktuelle Adresse aufgeloest" do
    mit_server do |basis|
      html = @proc.send(:fetch_html, "#{basis}/kurz")
      assert_includes html, "Angekommen", "die Weiterleitung muss ankommen, nicht scheitern"
    end
  end

  test "Weiterleitung auf ein fremdes Schema meldet, was los ist" do
    mit_server do |basis|
      fehler = assert_raises(RuntimeError) { @proc.send(:fetch_html, "#{basis}/woanders") }
      assert_match(/mailto/, fehler.message, "der Grund gehoert in die Meldung")
      refute_match(/not an HTTP URI/, fehler.message)
    end
  end

  test "Weiterleitung ohne Ziel meldet, was los ist" do
    mit_server do |basis|
      fehler = assert_raises(RuntimeError) { @proc.send(:fetch_html, "#{basis}/ohne-ziel") }
      assert_match(/ohne Ziel/, fehler.message)
    end
  end

  # ── #1471: Quelle wurde nicht angelegt ──────────────────────────────────
  #
  # Hans: „Es wurde auch keine Quelle angelegt. Woran liegt das?" — Der Titel
  # wird fuer den Slug auf 40 Zeichen gekuerzt, und wenn dort ein Wort endet,
  # blieb ein Bindestrich stehen. Den lehnt die Slug-Pruefung der Quelle ab,
  # `upsert_source` verschluckte den Fehler und lieferte nil: kein Quellen-
  # Eintrag, keine Meldung, nichts.
  test "abgeschnittener Titel erzeugt keinen Slug mit Bindestrich am Ende" do
    slug = @proc.send(:build_slug, "https://www.faz.net/-3br9ks",
                      "Albrecht Ritschl: Gegen Furcht vor einer KI-Superintelligenz")
    refute slug.end_with?("-"), "ein Slug endet nicht auf einem Bindestrich (war: #{slug})"
    assert_match(/\A[a-z0-9._-]+\z/, slug, "und besteht nur aus erlaubten Zeichen")
    assert slug.start_with?("faz-net-"), "der Rechnername bleibt vorn"
  end

  test "die so gebaute Quelle laesst sich wirklich speichern" do
    slug = @proc.send(:build_slug, "https://www.faz.net/-3br9ks",
                      "Albrecht Ritschl: Gegen Furcht vor einer KI-Superintelligenz")
    quelle = Source.new(slug: slug, csl_type: "webpage", title: "Titel",
                        url: "https://www.faz.net/-3br9ks", creator: @hans)
    assert quelle.valid?, "Slug wird von der Quelle akzeptiert: #{quelle.errors.full_messages}"
  end

  # Manche Seiten tragen als Autor eine Profil-Adresse ein (die FAZ ihre
  # Facebook-Seite). Daraus darf keine Person werden.
  test "eine Adresse ist kein Autorname" do
    assert_nil @proc.send(:autorname, "https://www.facebook.com/faz")
    assert_nil @proc.send(:autorname, "//example.org/x")
    assert_nil @proc.send(:autorname, "mailto:jemand@example.org")
    assert_nil @proc.send(:autorname, "  ")
    assert_equal "Albrecht Ritschl", @proc.send(:autorname, " Albrecht Ritschl ")
  end

  # ── #1471: Absaetze, die als <div> gesetzt sind ─────────────────────────
  #
  # Hans: „Die Inhalte unter diesen Zwischenueberschriften fehlen." — Die FAZ
  # setzt Absaetze als `div.p1` statt als <p>. Drei ganze Abschnitte (2.980
  # Zeichen) fielen deshalb heraus; die fett gesetzten Ueberschriften kamen
  # durch, weil sie <strong> sind, der Text darunter nicht. Der Artikel sah
  # dadurch zerpflueckt aus.
  DIV_SEITE = <<~HTML.freeze
    <html><body><article>
      <p>Ein ganz normaler Absatz, lang genug, um als Inhalt zu zaehlen und nicht
         als Beiwerk durchzufallen — hier steht Fliesstext.</p>
      <div class="p1"><strong>1. Die Datenbremse:</strong> Es fehlt an neuen Texten
         zur Fuetterung, und die Skalierung stoesst an Grenzen. Dieser Abschnitt ist
         lang genug, um als Absatz zu gelten, und enthaelt keinen einzigen Verweis.</div>
      <div class="teaser">Mehr zum Thema
         <a href="/a">Erster Verweis mit viel Text</a>
         <a href="/b">Zweiter Verweis mit viel Text</a>
         <a href="/c">Dritter Verweis mit ebenfalls viel Text darin</a></div>
      <div class="wrapper"><p>Ein Absatz in einem Wrapper-Div, lang genug fuer die
         Schwelle — er darf genau einmal erscheinen, nicht zweimal.</p></div>
    </article></body></html>
  HTML

  test "als div gesetzte Absaetze werden uebernommen" do
    body = @proc.send(:extract_body, DIV_SEITE)
    assert_includes body, "Die Datenbremse", "die Zwischenueberschrift"
    assert_includes body, "Es fehlt an neuen Texten", "und der Text darunter"
  end

  test "die Zwischenueberschrift steht genau einmal da" do
    body = @proc.send(:extract_body, DIV_SEITE)
    assert_equal 1, body.scan("Die Datenbremse").size,
                 "einmal aus dem Absatz — nicht zusaetzlich als eigenstaendiges <strong>"
  end

  test "verweislastige Kaesten bleiben draussen" do
    body = @proc.send(:extract_body, DIV_SEITE)
    refute_includes body, "Mehr zum Thema",
                    "ein Kasten, der fast nur aus Verweisen besteht, ist kein Absatz"
  end

  test "ein Wrapper-Div nimmt seinen Inhalt nicht ein zweites Mal mit" do
    body = @proc.send(:extract_body, DIV_SEITE)
    assert_equal 1, body.scan("Ein Absatz in einem Wrapper-Div").size
  end

  # ── #1471: Autoren-Kasten aus der Artikel-Fusszeile ─────────────────────
  #
  # Hans: „Wenn man den Autorenkasten zuverlaessig erkennen kann, kann er
  # meinetwegen mitkommen." — Man kann, an zwei Merkmalen zusammen: Er steht
  # in einer Fusszeile INNERHALB des Artikels (die HTML-Norm sieht `footer`
  # im `article` genau dafuer vor), und er liest sich wie ein Absatz.
  #
  # Das zweite Merkmal ist noetig, weil in derselben Fusszeile auch die
  # "Mehr zum Thema"-Teaser stehen — die kamen beim ersten Versuch als
  # Ueberschriften herein.
  FOOTER_SEITE = <<~HTML.freeze
    <html><body>
      <article>
        <p>Der eigentliche Artikeltext, lang genug um als Inhalt zu zaehlen und
           nicht als Beiwerk durchzufallen. Hier steht der Gedankengang.</p>
        <footer>
          <p>Albrecht Ritschl lehrt seit 2007 Wirtschaftsgeschichte an der London
             School of Economics. Auf die Insel zog es den Muenchner nach Jahren an
             der Humboldt-Universitaet und der Universitaet Zuerich.</p>
          <h2><a href="/x">Mehr zum Thema: Ein ganz anderer Artikel</a></h2>
          <p><a href="/y">Teilen</a> <a href="/z">Drucken</a> Merken</p>
        </footer>
      </article>
      <footer><p>Impressum Datenschutz Kontakt — die Fusszeile der ganzen Seite,
        die mit dem Artikel nichts zu tun hat und lang genug waere.</p></footer>
    </body></html>
  HTML

  test "der Autoren-Kasten aus der Artikel-Fusszeile kommt mit" do
    body = @proc.send(:extract_body, FOOTER_SEITE)
    assert_includes body, "lehrt seit 2007", "der Autoren-Kasten gehoert zum Artikel"
  end

  test "Teaser und Teilen-Leiste aus derselben Fusszeile bleiben draussen" do
    body = @proc.send(:extract_body, FOOTER_SEITE)
    refute_includes body, "Mehr zum Thema", "eine Teaser-Ueberschrift ist kein Absatz"
    refute_includes body, "Drucken", "und die Teilen-Leiste erst recht nicht"
  end

  test "die Fusszeile der SEITE bleibt weiterhin draussen" do
    body = @proc.send(:extract_body, FOOTER_SEITE)
    refute_includes body, "Impressum Datenschutz",
                    "nur Fusszeilen INNERHALB des Artikels zaehlen"
  end

  # Ohne erkannten <article> bleibt es beim alten Verhalten — sonst waere die
  # ganze Seite der Wurzelknoten und die Seiten-Fusszeile kaeme mit herein.
  test "ohne Artikel-Element bleiben Fusszeilen aussen vor" do
    ohne = "<html><body><p>#{'Ein Text ' * 20}</p>" \
           "<footer><p>#{'Fusszeile ' * 20}</p></footer></body></html>"
    body = @proc.send(:extract_body, ohne)
    refute_includes body, "Fusszeile"
  end

  # ── #1485: <article> heisst nicht Artikel ──────────────────────────────
  #
  # Hans: „Hier wurde wieder der Volltext nicht erkannt."
  #
  # Auf WordPress-Seiten ist JEDER Leserkommentar ein <article> — formal
  # richtig, die Norm meint mit <article> ein in sich geschlossenes Stueck
  # Inhalt, nicht den Hauptinhalt. Bei worldbeyondwar.org gab es sieben
  # <article>: fuenf Kommentare und zwei Teaser-Kacheln, der Brief selbst
  # stand in divs. Uebernommen wurde der laengste Kommentar.
  #
  # Die Seite hier ist danach gebaut: Kommentare als <article>, eine
  # Teaser-Kachel als <article>, der Beitrag im Inhalts-Container.
  WORDPRESS_SEITE = <<~HTML.freeze
    <html><body>
      <div class="elementor-widget-theme-post-content">
        <p>Sie haben wiederholt von der Verantwortung Deutschlands fuer die
           europaeische Sicherheit gesprochen. Diese Verantwortung laesst sich
           nicht mit Schlagworten einloesen.</p>
        <p>Seit 1990 sind die Sicherheitsbedenken wiederholt beiseitegeschoben
           worden — oft unter deutscher Beteiligung, und stets mit derselben
           Begruendung, die sich im Rueckblick nicht gehalten hat.</p>
      </div>
      <div id="comments"><ol class="comment-list">
        <li><article id="div-comment-15864" class="comment-body">
          <p>Ein Artikel, der mein Verstaendnis der Lage zwischen Europa und
             Russland erweitert hat. An meiner Sicht auf den Angriff hat er
             nichts geaendert. Putin ist nicht Russland.</p>
        </article></li>
      </ol></div>
      <article class="elementor-post"><h3>Basisarbeit und Aktivismus</h3></article>
    </body></html>
  HTML

  test "ein Leserkommentar wird nicht fuer den Artikel gehalten" do
    body = @proc.send(:extract_body, WORDPRESS_SEITE)
    assert_includes body, "Schlagworten einloesen", "der Beitrag gehoert herein"
    assert_includes body, "Seit 1990", "und zwar vollstaendig"
    refute_includes body, "Putin ist nicht Russland", "der Kommentar nicht"
  end

  test "eine Teaser-Kachel als <article> macht die Seite nicht zum Teaser" do
    body = @proc.send(:extract_body, WORDPRESS_SEITE)
    refute_includes body, "Basisarbeit und Aktivismus",
                    "ein <article> mit einem Bruchteil des Seitentextes ist nicht der Artikel"
  end

  # Die Gegenprobe zur Anteils-Schwelle: Ein echtes <article> bleibt die
  # Wurzel, auch wenn ringsherum noch Seiteninhalt steht. Ohne diesen Test
  # koennte die Schwelle unbemerkt so hoch wandern, dass sie richtige
  # Artikel verwirft — der Fall, der bis #1471 gut funktioniert hat.
  test "ein echtes <article> bleibt die Wurzel" do
    seite = "<html><body>" \
            "<article><p>#{'Der Artikeltext traegt den Grossteil der Seite. ' * 12}</p></article>" \
            "<div><p>#{'Beiwerk am Rand. ' * 5}</p></div>" \
            "</body></html>"
    body = @proc.send(:extract_body, seite)
    assert_includes body, "traegt den Grossteil"
    refute_includes body, "Beiwerk am Rand"
  end

  # Ohne <article> wird nicht sofort die ganze Seite genommen: Erst kommen
  # die benannten Inhalts-Container dran. Sonst haengt an einem sauber
  # erkannten Text noch der Spendenkasten und die Sprachauswahl.
  test "ein benannter Inhalts-Container schlaegt die ganze Seite" do
    seite = "<html><body>" \
            "<div class=\"entry-content\"><p>#{'Der Beitrag selbst. ' * 12}</p></div>" \
            "<div><h4>Related Articles</h4><p>#{'Spendenkasten und Sprachauswahl. ' * 4}</p></div>" \
            "</body></html>"
    body = @proc.send(:extract_body, seite)
    assert_includes body, "Der Beitrag selbst"
    refute_includes body, "Related Articles"
  end

  # Die Grenze der Container-Regel, an einer echten Messung festgehalten:
  # Der breitere Name `post-content` traf auf Substack (Clip #21) einen
  # Container OHNE Dachzeile und Untertitel — 512 Zeichen weg, darunter
  # echter Inhalt. Ein Container, der den Anfang abschneidet, ist schlimmer
  # als etwas Beiwerk am Ende. Deshalb steht er nicht in der Liste.
  test "ein Container, der die Dachzeile ausschliesst, wird nicht bevorzugt" do
    seite = "<html><body><div class=\"post\">" \
            "<h1>Die Ueberschrift</h1>" \
            "<h3>Der Untertitel, der den Artikel in einem Satz zusammenfasst.</h3>" \
            "<div class=\"post-content\"><p>#{'Der Fliesstext des Beitrags. ' * 12}</p></div>" \
            "</div></body></html>"
    body = @proc.send(:extract_body, seite)
    assert_includes body, "Der Untertitel", "der Untertitel ist Inhalt, kein Beiwerk"
    assert_includes body, "Der Fliesstext"
  end
end
