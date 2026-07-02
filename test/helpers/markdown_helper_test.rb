require "test_helper"

class MarkdownHelperTest < ActionView::TestCase
  test "render_inline_markdown rendert Markdown ohne <p>-Wrapper für Single-Line" do
    out = render_inline_markdown("Mit **Fett** und `code`.")
    assert_includes out, "<strong>Fett</strong>"
    assert_includes out, "<code>code</code>"
  end

  test "render_inline_markdown escaped HTML-Tags im Input" do
    out = render_inline_markdown("<script>alert('x')</script>")
    refute_includes out, "<script>"
  end

  # #475 (Hans, 2026-06-02): Antworten zeigen Backlink-Indikatoren auf
  # referenzierten Anker-Absaetzen — vorher nur im Voll-Render der KI.
  test "render_inline_markdown injiziert Backlink-Indikator fuer referenzierten Anker" do
    hans = create_human
    grant(hans, "KnowledgeItem", %w[read create update])
    with_isolated_miolimos_base do
      reply  = FileProxy.create(actor: hans, title: "r", item_type: :reply,
                                content: "Antwort-Absatz. ^a1b2c3d4\n")
      source = FileProxy.create(actor: hans, title: "Quelle", item_type: :note, content: "x")
      KnowledgeItemReference.create!(source_uuid: source.uuid, target_uuid: reply.uuid,
                                     target_title: "a1b2c3d4", anchor_type: "block",
                                     anchor_text: "a1b2c3d4")
      out = render_inline_markdown("Antwort-Absatz. ^a1b2c3d4", item: reply)
      assert_includes out, "backlink-indicator"
      assert_includes out, 'data-anchor="a1b2c3d4"'
      assert_includes out, "showBacklinks"
    end
  end

  test "render_inline_markdown ohne item injiziert keinen Indikator" do
    out = render_inline_markdown("Nur Text. ^a1b2c3d4")
    refute_includes out, "backlink-indicator"
  end

  # #450 (Hans, 2026-06-01): Replies/Kommentare rendern jetzt Highlights.
  test "render_inline_markdown rendert ==farbe|text== als <mark>" do
    out = render_inline_markdown("Ein ==rot|wichtiger== Punkt und ==gelb gelb==.")
    assert_includes out, %(<mark class="hl-rot">wichtiger</mark>)
    assert_includes out, %(<mark class="hl-gelb">gelb</mark>)
  end

  test "render_inline_markdown mit highlight_filter zeigt nur passende Marks" do
    out = render_inline_markdown("==rot|A== Mitte ==blau|B==", highlight_filter: ["rot"])
    assert_includes out, %(<mark class="hl-rot">A</mark>)
    refute_includes out, "hl-blau"
    refute_includes out, "Mitte"
  end

  test "render_inline_markdown mit highlight_filter ohne Treffer liefert leer" do
    out = render_inline_markdown("Kein Highlight hier", highlight_filter: ["rot"])
    assert_equal "", out.to_s.strip
  end

  # #465/#466 (Hans, 2026-06-02): block-N-IDs fuer paragraph-actions in
  # Antworten — Hover-Markierung + Kontextmenue brauchen ankerbare Bloecke.
  test "render_inline_markdown vergibt block-N-IDs an die Absatz-Bloecke" do
    out = render_inline_markdown("Erster Absatz.\n\nZweiter Absatz.")
    assert_match %r{<p id="block-1">Erster Absatz\.</p>}, out
    assert_match %r{<p id="block-2">Zweiter Absatz\.</p>}, out
  end

  test "render_inline_markdown: Mark im Block, block-ID am Block" do
    out = render_inline_markdown("Ein ==rot|wichtiger== Satz.")
    assert_match %r{<p id="block-1">.*<mark class="hl-rot">wichtiger</mark>.*</p>}, out
  end

  # #466 (Hans, 2026-06-02): nachgestellter ^id-Anker wird als Block-id
  # gehoben (Absatz ist per #id scrollbar; Link [[Parent^id|Thread-Antwort]]).
  test "render_inline_markdown hebt nachgestellten ^id-Anker als Block-id" do
    out = render_inline_markdown("Ein Absatz mit Anker ^a1b2c3d4")
    assert_match %r{<p id="a1b2c3d4">Ein Absatz mit Anker</p>}, out
    refute_includes out, "^a1b2c3d4"
  end
end
