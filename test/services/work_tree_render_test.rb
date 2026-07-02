require "test_helper"

# #378 (Hans, 2026-05-26): Tests fuer WorkTreeRender — Tree-Walk +
# HTML-Render aus #325 Phase 3a/3b.
class WorkTreeRenderTest < ActiveSupport::TestCase
  setup do
    @hans = create_human
    grant(@hans, "KnowledgeItem", %w[read create update delete])
    grant(@hans, "Topic", %w[read create update delete])
  end

  def create_ki(title, content = "")
    FileProxy.create(actor: @hans, title: title, item_type: :note, content: content)
  end

  def make_topic
    Topic.create!(name: "T", slug: "t-#{SecureRandom.hex(4)}", creator: @hans)
  end

  test "renders headings as h1..h6 capped at H6" do
    with_isolated_miolimos_base do
      topic = make_topic
      n1 = WorkNodeOps.create(topic: topic, knowledge_item: create_ki("A"), role: "heading")
      n2 = WorkNodeOps.create(topic: topic, knowledge_item: create_ki("B"), role: "heading", parent: n1)
      n3 = WorkNodeOps.create(topic: topic, knowledge_item: create_ki("C"), role: "heading", parent: n2)

      html = WorkTreeRender.call(topic)
      assert_match(/<h1>1\. A<\/h1>/,    html)
      assert_match(/<h2>1\.1\. B<\/h2>/, html)
      assert_match(/<h3>1\.1\.1\. C<\/h3>/, html)
    end
  end

  test "auto-numbering counts headings only (content nodes do not increment)" do
    with_isolated_miolimos_base do
      topic = make_topic
      h1 = WorkNodeOps.create(topic: topic, knowledge_item: create_ki("First"),  role: "heading")
      _c = WorkNodeOps.create(topic: topic, knowledge_item: create_ki("Inhalt"), role: "content")
      h2 = WorkNodeOps.create(topic: topic, knowledge_item: create_ki("Second"), role: "heading")

      html = WorkTreeRender.call(topic)
      assert_match(/<h1>1\. First<\/h1>/,  html)
      assert_match(/<h1>2\. Second<\/h1>/, html)
    end
  end

  test "sub-headings under a content node inherit the path of the preceding heading sibling" do
    with_isolated_miolimos_base do
      topic = make_topic
      # Tree: [H1, Content, H2 (extern)] mit Content.children = [SubH3, SubH4]
      h1 = WorkNodeOps.create(topic: topic, knowledge_item: create_ki("H1"), role: "heading")
      c  = WorkNodeOps.create(topic: topic, knowledge_item: create_ki("C"),  role: "content")
      WorkNodeOps.create(topic: topic, knowledge_item: create_ki("SubA"), role: "heading", parent: c)
      WorkNodeOps.create(topic: topic, knowledge_item: create_ki("SubB"), role: "heading", parent: c)
      WorkNodeOps.create(topic: topic, knowledge_item: create_ki("H2"), role: "heading")

      html = WorkTreeRender.call(topic)
      assert_match(/<h1>1\. H1<\/h1>/, html)
      # Children-Headings unter dem Content erben den Path von H1 (= last heading sibling).
      assert_match(/<h2>1\.1\. SubA<\/h2>/, html)
      assert_match(/<h2>1\.2\. SubB<\/h2>/, html)
      assert_match(/<h1>2\. H2<\/h1>/, html)
    end
  end

  test "number_headings: false omits the path prefix" do
    with_isolated_miolimos_base do
      topic = make_topic
      WorkNodeOps.create(topic: topic, knowledge_item: create_ki("H"), role: "heading")
      html = WorkTreeRender.call(topic, number_headings: false)
      assert_match(/<h1>H<\/h1>/, html)
      assert_no_match(/<h1>1\. H/, html)
    end
  end

  test "renders empty result when topic has no work-tree nodes" do
    with_isolated_miolimos_base do
      topic = make_topic
      assert_equal "", WorkTreeRender.call(topic)
    end
  end

  test "((Reference))-Wikilinks accumulate into a single footnotes section at the end" do
    with_isolated_miolimos_base do
      ref_a = create_ki("Quelle A")
      ref_b = create_ki("Quelle B")
      topic = make_topic
      WorkNodeOps.create(topic: topic, knowledge_item: create_ki("Eins", "Verweis ((Quelle A)).\n"), role: "heading")
      WorkNodeOps.create(topic: topic, knowledge_item: create_ki("Zwei", "Auch ((Quelle B)) und nochmal ((Quelle A)).\n"), role: "heading")

      html = WorkTreeRender.call(topic)
      # Footnote-Marker im Body
      assert_match(/sup class="reference-cite"/, html)
      # Eine zentrale Footnotes-Section am Ende.
      assert_match(/<section class="footnotes/, html)
      assert_equal 1, html.scan(/<section class="footnotes/).size
      # Dedup: 2 distinct references → 2 listed footnotes
      footnotes_html = html[/<section class="footnotes.*?<\/section>/m]
      assert_equal 2, footnotes_html.scan(/<li id="fn-\d+/).size
    end
  end
end
