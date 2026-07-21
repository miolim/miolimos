require "test_helper"

# #378 (Hans, 2026-05-26): Tests fuer KnowledgeMarkdown::References
# — Roam-Style ((Title))-Reference-Wikilinks aus #325 Phase 3b.
class KnowledgeMarkdown::ReferencesTest < ActiveSupport::TestCase
  setup do
    @hans = create_human
    grant(@hans, "KnowledgeItem", %w[read create update delete])
  end

  def create_ki(title)
    FileProxy.create(actor: @hans, title: title, item_type: :note, content: "x")
  end

  test "inline style renders existing reference as italic parens with link" do
    with_isolated_miolimos_base do
      target = create_ki("Quelle X")
      html = KnowledgeMarkdown::References.resolve(
        "Text ((Quelle X)) mehr.", style: :inline)
      assert_match(%r{<em class="reference-cite">}, html)
      assert_match(%r{href="/knowledge_items/#{target.uuid}"}, html)
    end
  end

  test "inline style flags missing reference with missing-class + tooltip" do
    html = KnowledgeMarkdown::References.resolve(
      "Text ((Phantom)) mehr.", style: :inline)
    assert_match(%r{reference-cite--missing}, html)
    assert_match(%r{title="\(\(Phantom\)\)}, html)
  end

  test "footnote style adds superscript markers + footnotes section" do
    with_isolated_miolimos_base do
      a = create_ki("Quelle A")
      b = create_ki("Quelle B")
      html = KnowledgeMarkdown::References.resolve(
        "Eins ((Quelle A)) zwei ((Quelle B)).", style: :footnote)
      assert_match(%r{<sup class="reference-cite">}, html)
      assert_match(%r{href="#fn-1"}, html)
      assert_match(%r{href="#fn-2"}, html)
      assert_match(%r{<section class="footnotes}, html)
      assert_match(%r{href="/knowledge_items/#{a.uuid}"}, html)
      assert_match(%r{href="/knowledge_items/#{b.uuid}"}, html)
    end
  end

  test "footnote dedup: same title twice gets same fn-index and only-first-id" do
    with_isolated_miolimos_base do
      create_ki("Quelle A")
      html = KnowledgeMarkdown::References.resolve(
        "Erst ((Quelle A)), dann nochmal ((Quelle A)).", style: :footnote)
      # Beide Marker zeigen auf #fn-1
      assert_equal 2, html.scan(/href="#fn-1"/).size
      # Aber nur EINE der zwei sup-Marker hat id="fnref-1" (duplicate-ID-frei).
      assert_equal 1, html.scan(/id="fnref-1"/).size
      # Footnote-Liste hat genau einen Eintrag.
      assert_equal 1, html.scan(/<li id="fn-/).size
    end
  end

  test "collector accumulates references across multiple resolve calls" do
    with_isolated_miolimos_base do
      create_ki("Quelle A")
      create_ki("Quelle B")
      coll = KnowledgeMarkdown::References::Collector.new
      KnowledgeMarkdown::References.resolve("((Quelle A))", style: :footnote, collector: coll)
      KnowledgeMarkdown::References.resolve("((Quelle B))", style: :footnote, collector: coll)
      footnotes = coll.to_html
      assert_match(%r{Quelle A}, footnotes)
      assert_match(%r{Quelle B}, footnotes)
      assert_equal 2, footnotes.scan(/<li id="fn-/).size
    end
  end
end
