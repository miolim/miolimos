require "test_helper"

class KnowledgeMarkdown::WikilinksTest < ActiveSupport::TestCase
  def make_ki(title, **attrs)
    with_isolated_miolimos_base do
      hans = create_human
      grant(hans, "KnowledgeItem", %w[create])
      return FileProxy.create(actor: hans, title: title, item_type: :note,
                              content: attrs[:content] || "")
    end
  end

  test "resolve links to an existing KI by title" do
    ki = make_ki("Sample Note")
    html = KnowledgeMarkdown::Wikilinks.resolve("a [[Sample Note]] link")
    assert_match %r{<a href="/knowledge_items/#{ki.uuid}"}, html
    assert_match %r{class="wikilink}, html
    assert_match %r{Sample Note</a>}, html
  end

  # #692 (Hans): bei mehreren/geschachtelten `[[` matcht das ENGSTE
  # Klammerpaar — ein vorangestelltes loses `[[` bleibt literaler Text.
  test "resolve matcht das engste [[…]] bei vorangestelltem losem [[" do
    ki = make_ki("Sample Note")
    html = KnowledgeMarkdown::Wikilinks.resolve("[[ lose Klammer [[Sample Note]] dahinter")
    assert_includes html, %(href="/knowledge_items/#{ki.uuid}")
    assert_includes html, ">Sample Note</a>"   # Linktext = nur der innere Titel
    assert_includes html, "[[ lose Klammer"     # Vortext bleibt literal
    refute_includes html, ">[[Sample Note"      # kein `[[` im Linktext
  end

  test "resolve renders a missing-target link for unknown titles" do
    html = KnowledgeMarkdown::Wikilinks.resolve("ref [[Does Not Exist]]")
    assert_match %r{wikilink-missing}, html
    assert_match %r{data-target-title="Does Not Exist"}, html
  end

  test "resolve carries block-anchor into href and data attribute" do
    ki = make_ki("Anchored")
    # #239 Phase B: 6-Zeichen base36 wird als Relation-Anchor erkannt
    # (eigener Pfad), nicht als Block-Anchor. Hier nutzen wir einen
    # nicht-base36-Anker, um den Block-Anchor-Pfad zu testen.
    html = KnowledgeMarkdown::Wikilinks.resolve("see [[Anchored^block-3]]")
    assert_match %r{href="/knowledge_items/#{ki.uuid}#block-3"}, html
    assert_match %r{data-target-anchor="block-3"}, html
  end

  test "resolve respects an alias label" do
    make_ki("Alpha")
    html = KnowledgeMarkdown::Wikilinks.resolve("[[Alpha|the first one]]")
    assert_match %r{>the first one</a>}, html
  end

  test "lookup_target finds KI by UUID, title, and alias" do
    ki = make_ki("UUIDFinder")
    found_by_uuid  = KnowledgeMarkdown::Wikilinks.lookup_target(ki.uuid)
    assert_equal ki.uuid, found_by_uuid.uuid

    found_by_title = KnowledgeMarkdown::Wikilinks.lookup_target("uuidfinder")  # case-insensitive
    assert_equal ki.uuid, found_by_title.uuid

    ki.update!(aliases: ["aka-finder"])
    found_by_alias = KnowledgeMarkdown::Wikilinks.lookup_target("aka-finder")
    assert_equal ki.uuid, found_by_alias.uuid

    assert_nil KnowledgeMarkdown::Wikilinks.lookup_target("nope")
  end

  test "resolve HTML-escapes the visible label" do
    html = KnowledgeMarkdown::Wikilinks.resolve("[[<script>|<b>x</b>]]")
    refute_includes html, "<script>"
    refute_includes html, "<b>x</b>"
    assert_includes html, "&lt;b&gt;x&lt;/b&gt;"
  end

  # #155: Alias-Slot mit URL → kein Display-Alias, sondern Hinweis-URL
  # für späteres Entity-Import. Display bleibt der Title.
  test "resolve treats a URL in alias-slot as data-source-url on missing wikilinks" do
    html = KnowledgeMarkdown::Wikilinks.resolve("[[Anna Schneider | https://lab.eth.ch/anna]]")
    assert_match %r{wikilink-missing}, html
    assert_match %r{data-target-title="Anna Schneider"}, html
    assert_match %r{data-source-url="https://lab.eth.ch/anna"}, html
    # Anzeigetext bleibt Title, NICHT die URL:
    assert_match %r{>Anna Schneider</a>}, html
    refute_match %r{>https://}, html
  end

  test "resolve carries data-source-url on resolved wikilinks too" do
    make_ki("Schneider Anna")
    html = KnowledgeMarkdown::Wikilinks.resolve("[[Schneider Anna | https://lab.eth.ch/anna]]")
    refute_match %r{wikilink-missing}, html
    assert_match %r{data-source-url="https://lab.eth.ch/anna"}, html
    assert_match %r{>Schneider Anna</a>}, html
  end

  test "non-URL alias still works as display alias" do
    make_ki("Alpha")
    html = KnowledgeMarkdown::Wikilinks.resolve("[[Alpha|the first one]]")
    assert_match %r{>the first one</a>}, html
    refute_match %r{data-source-url=}, html
  end

  test "tooltip mentions source URL when present on missing wikilink" do
    html = KnowledgeMarkdown::Wikilinks.resolve("[[Beta | https://example.com/x]]")
    assert_match %r{title="Fehlende Entität — Quelle: https://example.com/x"}, html
  end
end
