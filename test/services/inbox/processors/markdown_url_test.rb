require "test_helper"

# #799: Importer für Links auf .md-Dateien.
class Inbox::Processors::MarkdownUrlTest < ActiveSupport::TestCase
  P = Inbox::Processors::MarkdownUrl

  setup do
    @hans = create_human
    grant(@hans, "KnowledgeItem", %w[read create update delete])
    grant(@hans, "Source",        %w[read create update delete])
  end

  test "markdown_url? erkennt .md/.markdown/.mdx, sonst nichts" do
    assert P.markdown_url?("https://europe2031.ai/agents/scenario.md")
    assert P.markdown_url?("https://x.io/readme.MARKDOWN")
    assert P.markdown_url?("https://x.io/a.mdx?ref=1")
    refute P.markdown_url?("https://x.io/page")
    refute P.markdown_url?("https://x.io/a.md.html")
    refute P.markdown_url?("https://youtube.com/watch?v=abc")
    refute P.markdown_url?("")
  end

  test "suggested_processor_kind schlägt markdown_url für .md-Links vor" do
    item = InboxItem.create!(creator: @hans, source_kind: "web_url",
                             source_url: "https://europe2031.ai/agents/scenario.md", status: "pending")
    assert_equal "markdown_url", item.suggested_processor_kind
    web = InboxItem.create!(creator: @hans, source_kind: "web_url",
                            source_url: "https://example.com/artikel", status: "pending")
    assert_equal "web_clip", web.suggested_processor_kind
  end

  test "process! legt formattreue KI an (Titel aus H1) + verlinkt die URL als Source" do
    with_isolated_miolimos_base do
      md = "# Szenario 2031\n\nEin **fetter** Absatz.\n\n## Details\n\n- Punkt A\n- Punkt B\n"
      item = InboxItem.create!(creator: @hans, source_kind: "web_url",
                               source_url: "https://europe2031.ai/agents/scenario.md", status: "pending")
      proc_ = P.new
      proc_.define_singleton_method(:fetch_markdown) { |_url, **| md }
      proc_.process!(item, actor: @hans)

      ki = KnowledgeItem.order(:created_at).last
      assert_equal "Szenario 2031", ki.title
      assert_includes ki.body, "**fetter**"
      assert_includes ki.body, "## Details"
      assert_includes ki.body, "- Punkt A"
      assert Source.exists?(url: "https://europe2031.ai/agents/scenario.md"), "URL als Source verlinkt"
    end
  end

  test "process! nutzt Frontmatter-title falls vorhanden" do
    with_isolated_miolimos_base do
      md = "---\ntitle: Offizieller Titel\ntype: note\n---\n\n# Andere H1\n\nInhalt.\n"
      item = InboxItem.create!(creator: @hans, source_kind: "web_url",
                               source_url: "https://x.io/doc.md", status: "pending")
      proc_ = P.new
      proc_.define_singleton_method(:fetch_markdown) { |_url, **| md }
      proc_.process!(item, actor: @hans)
      assert_equal "Offizieller Titel", KnowledgeItem.order(:created_at).last.title
    end
  end
end
