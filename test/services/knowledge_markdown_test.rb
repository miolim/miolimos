require "test_helper"

class KnowledgeMarkdownTest < ActiveSupport::TestCase
  setup do
    @hans = create_human
    grant(@hans, "KnowledgeItem", %w[read create update delete])
  end

  def render(md, item: nil)
    KnowledgeMarkdown.render(md, item: item)
  end

  # #488 (Hans, 2026-06-04): Aufgaben-Referenz [[#id]].
  test "task reference [[#id]] renders #id + title and links into the stack" do
    task = create_task(creator: @hans, title: "Überarbeitung der Navigationsleiste")
    html = render("Siehe [[##{task.id}]] dazu.")
    assert_includes html, "wikilink-task"
    assert_includes html, %(data-target-uuid="task:#{task.id}")
    assert_includes html, "##{task.id} Überarbeitung der Navigationsleiste"
  end

  test "task reference accepts an explicit alias [[#id|Label]]" do
    task = create_task(creator: @hans, title: "Irgendwas")
    html = render("[[##{task.id}|Mein Label]]")
    assert_includes html, ">Mein Label</a>"
  end

  test "unknown task reference renders a missing marker" do
    html = render("[[#99999999]]")
    assert_includes html, "wikilink-missing"
    assert_includes html, "#99999999"
  end

  # #512 (Hans, 2026-06-04): Zitier-Schalter + no_intra_emphasis.
  test "citation switches |y and |a control the label; underscore slug not emphasized" do
    person = KnowledgeItem.create!(uuid: SecureRandom.uuid, title: "R Bjork", item_type: "person",
      last_name: "Bjork", file_path: "k/#{SecureRandom.hex(4)}.md", content_hash: SecureRandom.hex(32))
    src = Source.create!(slug: "bjork_1994_x", title: "Mem", csl_type: "book",
      issued_string: "1994", creator: @hans)
    SourceCreator.create!(source: src, knowledge_item: person, role: "author", position: 0)

    assert_includes render("[@bjork_1994_x|y]"), "(1994)"
    assert_match(/Bjork/, render("[@bjork_1994_x|a]"))
    # no_intra_emphasis: der Underscore-Slug wird nicht zu <em> zerlegt,
    # die Zitat-Auflösung greift also.
    html = render("[@bjork_1994_x]")
    refute_includes html, "<em>"
    assert_includes html, "source-cite"
  end

  # #519 (Hans, 2026-06-05): @-Mention am Absatz-Anfang (hinter `<p>`) muss
  # rendern, nicht nur mitten im Text.
  test "@-mention at the start of a paragraph renders as an actor-mention span" do
    start_html = render("@hans steht am Absatzanfang")
    mid_html   = render("Frag mal @hans dazu")
    assert_includes start_html, "actor-mention", "mention at line start must render"
    assert_includes mid_html,   "actor-mention"
  end

  test "renders plain markdown to HTML" do
    html = render("# Hallo\n\nWelt.")
    # #341: Headings sind jetzt anker-faehig und bekommen einen id-
    # Attribut (block-N oder ^stable-id) via inject_block_ids.
    assert_match(/<h1[^>]*>Hallo<\/h1>/, html)
    assert_match(/<p[^>]*>Welt\.<\/p>/, html)
  end

  test "block anchor `^id` becomes id attribute on the surrounding paragraph" do
    html = render("Erster Absatz. ^a1\n\nZweiter Absatz.\n")
    assert_match(/<p id="a1">Erster Absatz\.\s*<\/p>/, html)
  end

  test "wikilink to existing KI by title produces emerald link with data-target-uuid" do
    with_isolated_miolimos_base do
      target = FileProxy.create(actor: @hans, title: "Andere Notiz",
                                item_type: :note, content: "x")
      html = render("Siehe [[Andere Notiz]] dort.")
      assert_match %(data-target-uuid="#{target.uuid}"), html
      assert_match "wikilink", html
      assert_match ">Andere Notiz</a>", html
      refute_match "data-target-anchor", html
    end
  end

  # #500 (Hans, 2026-06-04): YAML-Frontmatter wird NICHT als Inhalt gerendert
  # und verschiebt die Block-Nummerierung nicht.
  test "Leading-Frontmatter wird nicht gerendert und Block-1 ist der erste Inhalt" do
    md = "---\ntyp: note\nbaut_auf: [[Irgendwas]]\n---\n\nErster echter Absatz.\n\nZweiter."
    html = render(md)
    assert_no_match(/typ: note/, html)
    assert_no_match(/baut_auf/, html)
    assert_match(/<p id="block-1">Erster echter Absatz\.<\/p>/, html)
  end

  test "ohne Frontmatter unveraendert" do
    html = render("Kein Frontmatter hier.\n\nZweiter Absatz.")
    assert_match(/<p id="block-1">Kein Frontmatter hier\.<\/p>/, html)
  end

  # #500 (Hans, 2026-06-04): `---` ohne Leerzeile davor soll als <hr> rendern,
  # nicht die Vorzeile zur Setext-Überschrift machen.
  test "--- ohne Leerzeile davor wird zu hr, nicht zu Setext-Überschrift" do
    html = render("Eine ganz normale Zeile\n---\nDanach.")
    assert_match(/<p[^>]*>Eine ganz normale Zeile<\/p>/, html)
    assert_match(/<hr\s*\/?>/, html)
    assert_no_match(/<h2[^>]*>Eine ganz normale Zeile/, html)
  end

  test "echte ATX-Überschrift bleibt Überschrift" do
    html = render("## Echte Überschrift\n\nText.")
    assert_match(/<h2[^>]*>Echte Überschrift<\/h2>/, html)
  end

  test "--- in einem Code-Block bleibt unberührt" do
    html = render("```\nfoo\n---\nbar\n```")
    assert_match(/<pre><code>foo\s*---\s*bar/, html)
    assert_no_match(/<hr/, html)
  end

  # #498 (Hans, 2026-06-03): in verschachtelten Listen bekommen ALLE
  # Listenpunkte ein block-N (vorher nur die Blaetter — Eltern-Punkte
  # wurden uebersprungen, daher kein Absatz-Highlight).
  test "verschachtelte Listenpunkte bekommen alle eine block-id" do
    html = render("- A\n  - B\n  - C\n- D\n  - E\n    - F\n")
    li_total   = html.scan(/<li\b/).size
    li_with_id = html.scan(/<li[^>]*\bid="block-\d+"/).size
    assert_equal li_total, li_with_id, "jeder Listenpunkt soll ein block-N tragen"
    assert_equal 6, li_with_id
  end

  test "Mehr-Absatz-Listenpunkt bleibt Wrapper (li ohne id, <p> tragen sie)" do
    # Loose list item mit zwei echten Absaetzen -> <li><p>..</p><p>..</p></li>
    html = render("1.  Erster Absatz.\n\n    Zweiter Absatz.\n")
    # li ist Wrapper (hat direkte <p>) -> keine id; die <p> bekommen sie.
    assert_no_match(/<li[^>]*\bid="block-/, html)
    assert_operator html.scan(/<p[^>]*\bid="block-\d+"/).size, :>=, 2
  end

  # #496 (Hans, 2026-06-03): `==…==` in Inline-/Fenced-Code zaehlt NICHT
  # als Highlight (sonst Phantom-Filter ohne sichtbare Mark im Text).
  test "highlight_counts ignoriert == in Inline-Code" do
    assert_equal({}, KnowledgeMarkdown.highlight_counts("Syntax `==gelb|x==^a1b2c3d4` erklaert."))
  end

  test "highlight_counts ignoriert == in Fenced-Code" do
    body = "Beispiel:\n\n```\n==farbe|text==^id\n```\n\nEnde."
    assert_equal({}, KnowledgeMarkdown.highlight_counts(body))
  end

  test "highlight_counts zaehlt echte Highlights ausserhalb von Code" do
    assert_equal({ "gelb" => 1 }, KnowledgeMarkdown.highlight_counts("Ein ==gelb|wort==^a1b2c3d4 hier."))
    assert_equal({ "gelb" => 1 }, KnowledgeMarkdown.highlight_counts("Bare ==markiert== Default-gelb."))
  end

  # #488 (Hans, 2026-06-03): `((` in Inline-Code darf den `((…))`-Resolver
  # nicht ausloesen und kein HTML zerreissen (sonst lief die Monospace-
  # Schrift im ganzen Thread „durch"). Code-Spans muessen balanciert bleiben.
  test "(( in Inline-Code zerreisst das HTML nicht" do
    html = render("Roam-Style `((` ist belegt — siehe ((Echte Notiz)).")
    assert_equal html.scan(/<code[ >]/).size, html.scan(/<\/code>/).size,
                 "code-Tags muessen balanciert sein"
    # das `((` im Code bleibt unaufgeloest
    assert_match %r{<code>\(\(</code>}, html
  end

  # #667-Folge (Hans): ein VOLLSTÄNDIGER [[…]]-Wikilink in Inline-Code
  # blieb nicht literal — er wurde zum Link gestempelt und der <a> landete
  # IM <code> ("Kraut und Rüben").
  test "[[…]]-Wikilink in Inline-Code bleibt literal, kein Link im code" do
    html = render("Beispiel: `[[@Name]]` ist die Syntax.")
    assert_match %r{<code>\[\[@Name\]\]</code>}, html
    refute_match %r{<code>[^<]*<a }, html, "kein <a> innerhalb von <code>"
  end

  test "[[…]]-Wikilink in Fenced-Code bleibt literal" do
    html = render("```\n[[Echte Notiz]]\n```")
    assert_includes html, "[[Echte Notiz]]"
    refute_match %r{<code>[^<]*<a }, html
  end

  test "echter [[…]]-Wikilink AUSSERHALB von Code wird weiter aufgeloest" do
    html = render("Code `[[@X]]` aber echt [[miolimOS - Link-Typen]] hier.")
    assert_match %r{<code>\[\[@X\]\]</code>}, html
    assert_match %r{class="[^"]*wikilink}, html   # der echte Link existiert
  end

  test "((Titel)) ausserhalb von Code wird weiterhin aufgeloest" do
    html = render("Verweis ((Irgendwas)).")
    assert_match "reference-cite", html
  end

  test "[@slug] in Inline-Code wird nicht als Zitat aufgeloest" do
    html = render("Die `[@slug]`-Syntax erklaert.")
    refute_match "source-cite", html
    assert_match %r{<code>\[@slug\]</code>}, html
  end

  # #488 (Hans, 2026-06-03): getypte Praefixe [[@Person]] / [[&Quelle]].
  test "[[@Name]] verlinkt eine Personen-KI (violett, @-Praefix)" do
    with_isolated_miolimos_base do
      p = FileProxy.create(actor: @hans, title: "Erika Mustermann",
                           item_type: :person, content: "x")
      html = render("Frag [[@Erika Mustermann]] mal.")
      assert_match "wikilink-person", html
      assert_match %(data-target-uuid="#{p.uuid}"), html
      assert_match ">@Erika Mustermann</a>", html
    end
  end

  test "[[@Name]] auf eine NOTIZ (keine Person) ist ein Miss" do
    with_isolated_miolimos_base do
      FileProxy.create(actor: @hans, title: "Kein Mensch", item_type: :note, content: "x")
      html = render("Test [[@Kein Mensch]].")
      assert_match "wikilink-missing", html
      assert_match "wikilink-person", html
    end
  end

  # #655 v3: Der Missing-Person-Span wurde von ActorMentions zerlegt
  # („Kein App-Nutzer mit Slug …") — jetzt <a> (mention-geschützt) mit
  # 🔍-Recherche-Indikator.
  test "[[@Name]] ohne Person: kein Actor-Mention-Mangling, Recherche-Einstieg da" do
    with_isolated_miolimos_base do
      src_ki = FileProxy.create(actor: @hans, title: "Interview-Quelle-KI", item_type: :note, content: "x")
      src = Source.create!(slug: "yt-glenn-#{SecureRandom.hex(2)}", title: "Interview", csl_type: "webpage",
                           url: "https://www.youtube.com/watch?v=v8f73ueeSTw", creator: @hans)
      src_ki.update!(bib_source: src)
      html = render("Interview mit [[@Glenn Whale]] gestern.", item: src_ki)
      assert_match "wikilink-missing", html
      assert_match "wikilink-person", html
      assert_match ">@Glenn Whale</a>", html
      refute_match "actor-mention-missing", html
      refute_match "Kein App-Nutzer", html
      assert_match "research", html   # 🔍-Indikator (start_research), braucht source_item
    end
  end

  test "[[&slug]] verlinkt eine Quelle (amber)" do
    with_isolated_miolimos_base do
      src = Source.create!(title: "Müller 2024", slug: "mueller2024",
                           csl_type: "webpage", creator: @hans)
      html = render("Siehe [[&mueller2024]].")
      assert_match "wikilink-source", html
      assert_match %(href="/sources/mueller2024"), html
    end
  end

  test "[[&unbekannt]] ist ein Quellen-Miss" do
    html = render("Siehe [[&gibt-es-nicht]].")
    assert_match "wikilink-missing", html
    assert_match "wikilink-source", html
  end

  test "wikilink with block anchor `[[uuid^anchor|alias]]` adds data-target-anchor" do
    with_isolated_miolimos_base do
      target = FileProxy.create(actor: @hans, title: "Quelle",
                                item_type: :note, content: "x")
      html = render("[[#{target.uuid}^abc|↳ Source]]")
      assert_match %(data-target-uuid="#{target.uuid}"), html
      assert_match %(data-target-anchor="abc"), html
      assert_match %(href="/knowledge_items/#{target.uuid}#abc"), html
      assert_match ">↳ Source</a>", html
    end
  end

  test "wikilink to missing KI is rendered as missing-link with target-title" do
    html = render("[[Existiert nicht]]")
    assert_match "wikilink-missing", html
    assert_match %(data-target-title="Existiert nicht"), html
  end

  test "external http links get target=_blank and an external icon" do
    html = render("Quelle: https://example.com/seite")
    assert_match %(target="_blank"), html
    assert_match %(rel="noopener"), html
    assert_match "<svg", html  # external-link icon
  end

  test "links to own domain are NOT marked external" do
    html = render("Intern: https://os.miolim.de/some/page")
    refute_match %(target="_blank"), html
  end

  test "backlink indicator appears on anchored paragraphs that have references" do
    with_isolated_miolimos_base do
      target = FileProxy.create(actor: @hans, title: "Ziel",
                                item_type: :note,
                                content: "Hier ist ein Block. ^xyz\n")
      source = FileProxy.create(actor: @hans, title: "Quelle",
                                item_type: :note,
                                content: "[[#{target.uuid}^xyz|↳ Hier]]\n")
      # Indexer hat ggf. schon eine Reference angelegt — egal, wir prüfen
      # nur, dass der Indikator mit der richtigen Source-UUID rauskommt.
      KnowledgeItemReference.find_or_create_by!(
        source_uuid: source.uuid, target_uuid: target.uuid,
        anchor_type: "block", anchor_text: "xyz"
      ) { |r| r.target_title = target.title }
      html = KnowledgeMarkdown.render(
        FileProxy.read_body(actor: @hans, knowledge_item: target),
        item: target
      )
      assert_match "backlink-indicator", html
      assert_match %(data-anchor="xyz"), html
      assert_match(/data-source-uuids="[^"]*#{source.uuid}[^"]*"/, html)
    end
  end

  test "unknown citations are rendered as broken markers" do
    html = render("Wie [@gibt-es-nicht] gezeigt.")
    assert_match "source-cite-broken", html
    assert_match "[@gibt-es-nicht]", html
  end

  # #450 (Hans, 2026-06-01): highlight_counts zaehlt alle Syntaxen.
  test "highlight_counts zaehlt prefix, suffix und default-gelb" do
    counts = KnowledgeMarkdown.highlight_counts(
      "==rot|a== und ==b|blau== und ==c== und ==rot|d=="
    )
    assert_equal 2, counts["rot"]   # prefix a + prefix d
    assert_equal 1, counts["blau"]  # suffix b
    assert_equal 1, counts["gelb"]  # default c
  end

  # #450: apply_highlights_to rendert <mark> in fertigem HTML.
  test "apply_highlights_to rendert marks und filtert" do
    html = "<p>Ein ==rot|x== und ==blau|y==</p>"
    full = KnowledgeMarkdown.apply_highlights_to(html)
    assert_includes full, %(<mark class="hl-rot">x</mark>)
    assert_includes full, %(<mark class="hl-blau">y</mark>)

    only_rot = KnowledgeMarkdown.apply_highlights_to(html, filter: ["rot"])
    assert_includes only_rot, %(<mark class="hl-rot">x</mark>)
    refute_includes only_rot, "hl-blau"

    assert_nil KnowledgeMarkdown.apply_highlights_to("<p>nichts</p>", filter: ["rot"])
  end

  # #543 (Hans, 2026-06-08): Im Inline-Renderer (Antworten) läuft
  # apply_highlights_to auf bereits gerendertem HTML. Ein Highlight um einen
  # Link enthält dann `href="…"` — das `=` darin sprengte vorher `[^=]`, der
  # Highlight blieb roh stehen. Regression: muss jetzt rendern.
  test "apply_highlights_to rendert Highlight um einen Link (= in href)" do
    html  = KnowledgeMarkdown.render(
      %q{==rot|Öffne **https://os.miolim.de/documents/preview** jetzt==^73fbba90}
    )
    final = KnowledgeMarkdown.apply_highlights_to(html)
    assert_includes final, %(<mark class="hl-rot" id="73fbba90">)
    assert_includes final, %(href="https://os.miolim.de/documents/preview")
    refute_includes final, "==rot|"   # kein roher Wrap mehr
  end

  # #750 (Hans, 2026-06-21): Ein Highlight, das INLINE-CODE enthält
  # (`==…`code`…==`), wurde vom Renderer zu `==…<code>…</code>…==`. Das alte
  # Splitten an `<code>` zerriss die beiden `==`-Delimiter → der Mark fehlte
  # in der Ansicht (im Edit-Rohtext blieb `==…==` stehen). Maskierung statt
  # Split: muss jetzt rendern — und `==` GANZ INNERHALB von Code literal lassen.
  test "Highlight mit Inline-Code rendert, == innerhalb von Code bleibt literal" do
    html = KnowledgeMarkdown.render("Ein ==gelb|poked by `cron` jetzt==^8e223891 Ende.")
    assert_includes html, %(<mark class="hl-gelb" id="8e223891">)
    assert_includes html, "<code>cron</code>"
    refute_includes html, "==gelb|"   # kein roher Wrap mehr

    # Highlight, das MIT Inline-Code beginnt (Null-Byte-Delimiter darf das
    # `==(?!\\s)`-Lookahead nicht brechen).
    starts = KnowledgeMarkdown.render("==gelb|`code` am Anfang== Ende.")
    assert_includes starts, "<mark"
    refute_includes starts, "==gelb|"

    # Regression: `==…==` KOMPLETT in Inline-/Fenced-Code bleibt unmarkiert.
    inline = KnowledgeMarkdown.render("Syntax `==gelb|x==` bleibt Code.")
    refute_includes inline, "<mark"
    assert_includes inline, "==gelb|x=="
    fenced = KnowledgeMarkdown.render("```\n==gelb|x==\n```\n")
    refute_includes fenced, "<mark"
  end

  # #452 (Hans, 2026-06-01): Filter-Modus wrappt jede Mark in einen
  # .hl-filter-block — damit paragraph-actions das Highlight-Menue
  # (Tags etc.) auch im Filter-Modus per Rechtsklick erreichbar macht.
  test "Filter-Modus wrappt Marks in .hl-filter-block und behaelt die Anker-id" do
    html = KnowledgeMarkdown.render("==rot|A==^a1b2c3d4 und ==blau|B==",
                                    highlight_filter: ["rot"])
    assert_includes html, "hl-filter-block"
    assert_match %r{<p class="hl-filter-block[^"]*"><mark class="hl-rot" id="a1b2c3d4">A</mark></p>}, html
    refute_includes html, "hl-blau"
  end

  # #673 (Hans): zwischen zwei Highlights die Wortzahl der Luecke zeigen.
  test "Filter-Modus zeigt die Wortzahl zwischen zwei Highlights" do
    md = "==gelb|A== ein zwei drei vier ==gelb|B== und ==gelb|C=="
    html = KnowledgeMarkdown.render(md, highlight_filter: ["gelb"])
    assert_match(/4 Wörter dazwischen/, html)   # A→B: ein zwei drei vier
    assert_match(/1 Wort dazwischen/, html)      # B→C: und (Singular)
    # genau zwei Lueckenlabels bei drei Marks
    assert_equal 2, html.scan(/dazwischen/).size
  end

  # #675 (Hans): Backlink-Indikator eines Highlights muss auch im
  # Filter-Modus mitkommen (haengt direkt hinter dem </mark>).
  test "Filter-Modus behaelt den Backlink-Indikator des Highlights" do
    with_isolated_miolimos_base do
      target = FileProxy.create(actor: @hans, title: "Filter-Ziel", item_type: :note,
                                content: "Vorher ==gelb|wichtige Stelle==^a1b2c3d4 nachher.\n")
      FileProxy.create(actor: @hans, title: "Filter-Quelle", item_type: :note,
                       content: "[[Filter-Ziel^a1b2c3d4]]\n")
      html = KnowledgeMarkdown.render(
        FileProxy.read_body(actor: @hans, knowledge_item: target),
        item: target, highlight_filter: ["gelb"]
      )
      assert_includes html, "hl-filter-block"
      assert_includes html, "backlink-indicator"
      assert_match %(data-anchor="a1b2c3d4"), html
    end
  end

  # #466 (Hans, 2026-06-02): nackte Block-Anker (6-stellig, von
  # ensure_anchor) werden indiziert. 8-Hex-Highlight-Anker laufen ueber
  # ANCHOR_IN_BODY_RE und matchen den `[ \t]\^`-Bare-Scan NICHT.
  test "Anchors.extract erfasst nackte 6-stellige Block-Anker" do
    res = KnowledgeMarkdown::Anchors.extract("Ein Absatz mit Anker ^9wgjh9\n")
    assert_equal [], res["9wgjh9"]
  end

  # #466 (Hans, 2026-06-02): Anker-Kollision (selber Anker in zwei KIs)
  # darf den Save NICHT brechen — die Uniqueness-Validierung wirft
  # RecordInvalid, das sync_for schlucken muss.
  test "Anchors.sync_for bricht nicht bei bereits vergebenem Anker" do
    with_isolated_miolimos_base do
      a = FileProxy.create(actor: @hans, title: "A", item_type: :note, content: "x")
      b = FileProxy.create(actor: @hans, title: "B", item_type: :note, content: "y")
      KnowledgeItemAnchor.create!(anchor: "abc123", knowledge_item_uuid: a.uuid)
      assert_nothing_raised do
        KnowledgeMarkdown::Anchors.sync_for(b, "Ein Absatz ^abc123\n")
      end
      assert_equal a.uuid, KnowledgeItemAnchor.find_by(anchor: "abc123").knowledge_item_uuid
    end
  end

  # #466: [[^anker|alias]] aus einer ANTWORT loest auf den Parent auf —
  # mit dem realen 6-stelligen Block-Anker-Format (ensure_anchor).
  test "Anchor-only-Link einer Task-Antwort zeigt auf die Aufgabe" do
    with_isolated_miolimos_base do
      task  = Task.create!(title: "Eltern-Task", creator: @hans, status: :open)
      reply = FileProxy.create(actor: @hans, title: "r", item_type: :reply,
                               content: "Antwort-Absatz ^9wgjh9\n")
      reply.update!(title: nil, parent_type: "Task", parent_id_int: task.id,
                    published_at: Time.current)
      KnowledgeItemAnchor.find_or_create_by!(anchor: "9wgjh9", knowledge_item_uuid: reply.uuid)

      html = KnowledgeMarkdown.render("Siehe [[^9wgjh9|Thread-Antwort]].")
      assert_includes html, %(href="/tasks?stack=task:#{task.id}#9wgjh9")
      assert_includes html, ">Thread-Antwort</a>"
    end
  end

  # #561: juristische Gliederungs-Aufzählungen (1)/(2) + a)/b) als Listen.
  test "legal enumerations (1)/(2) and a)/b) render as nested lists" do
    md = "## Pflichten\n(1) erstens,\na) unterpunkt a,\nb) unterpunkt b\n(2) zweitens\n"
    html = render(md)
    assert_includes html, %(<ol class="legal-paren-decimal">)
    assert_includes html, %(<ol class="legal-paren-alpha">)
    assert_includes html, "erstens"
    assert_includes html, "unterpunkt a"
    assert_includes html, "zweitens"
    # Token sind wieder entfernt
    refute_includes html, "LP"
    refute_includes html, "LA"
  end

  test "stray (1) without enumeration context still renders" do
    md = "Nur ein Satz mit (1) Klammer mitten im Text.\n"
    html = render(md)
    assert_includes html, "(1) Klammer mitten im Text"
  end
end