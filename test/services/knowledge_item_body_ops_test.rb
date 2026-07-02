require "test_helper"

class KnowledgeItemBodyOpsTest < ActiveSupport::TestCase
  setup do
    @hans = create_human
    grant(@hans, "KnowledgeItem", %w[read create update delete])
  end

  def make_item(content)
    FileProxy.create(actor: @hans, title: "Quelle",
                     item_type: :note, content: content)
  end

  test "resolve_anchor! returns existing anchor as-is" do
    with_isolated_miolimos_base do
      item = make_item("Body. ^abc\n")
      assert_equal "abc",
        KnowledgeItemBodyOps.new(item, actor: @hans).resolve_anchor!("abc")
    end
  end

  test "resolve_anchor! creates a stable anchor for block-N" do
    with_isolated_miolimos_base do
      item = make_item("Eins.\n\nZwei.\n\nDrei.\n")
      anchor = KnowledgeItemBodyOps.new(item, actor: @hans).resolve_anchor!("block-2")
      assert anchor.present?
      body = FileProxy.read_body(actor: @hans, knowledge_item: item)
      assert_match(/Zwei\.\s+\^#{anchor}\b/, body)
    end
  end

  test "resolve_anchor! raises when block index is out of range" do
    with_isolated_miolimos_base do
      item = make_item("Nur ein Absatz.\n")
      assert_raises(ArgumentError) do
        KnowledgeItemBodyOps.new(item, actor: @hans).resolve_anchor!("block-9")
      end
    end
  end

  test "comment_at creates a Comment-KI with the wikilink-header back to the source" do
    with_isolated_miolimos_base do
      item = make_item("Erster Absatz hier. ^xyz\n")
      comment, anchor = KnowledgeItemBodyOps.new(item, actor: @hans).comment_at("xyz")

      assert_equal "xyz", anchor
      assert_match(/\AKommentar zu: /, comment.title)
      body = FileProxy.read_body(actor: @hans, knowledge_item: comment)
      assert_match "[[#{item.uuid}^xyz|↳ #{item.title}]]", body
      assert_includes comment.tags, "kommentar"
    end
  end

  test "comment_at sets a fresh anchor when given block-N for an unanchored block" do
    with_isolated_miolimos_base do
      item = make_item("A.\n\nB.\n")
      comment, anchor = KnowledgeItemBodyOps.new(item, actor: @hans).comment_at("block-2")

      refute_equal "block-2", anchor
      body = FileProxy.read_body(actor: @hans, knowledge_item: item)
      assert_match(/B\.\s+\^#{anchor}\b/, body)
      comment_body = FileProxy.read_body(actor: @hans, knowledge_item: comment)
      assert_match "[[#{item.uuid}^#{anchor}|↳", comment_body
    end
  end

  test "append_quote creates a quotes-collection KI on first call and re-uses it on second" do
    with_isolated_miolimos_base do
      pdf = FileProxy.create(actor: @hans, title: "Mein PDF",
                             item_type: :transcript, content: "x")
      ops = KnowledgeItemBodyOps.new(pdf, actor: @hans)

      collection1, created1 = ops.append_quote("Zitat eins.")
      assert created1
      assert_equal "Quotes aus Mein PDF", collection1.title

      collection2, created2 = ops.append_quote("Zitat zwei.\nMehrzeilig.")
      refute created2
      assert_equal collection1.uuid, collection2.uuid

      body = FileProxy.read_body(actor: @hans, knowledge_item: collection2)
      assert_match "> Zitat eins.",      body
      assert_match "> Zitat zwei.",      body
      assert_match "> Mehrzeilig.",      body
      assert_match "[[#{pdf.uuid}|↳",    body
    end
  end

  test "append_quote raises on empty input" do
    with_isolated_miolimos_base do
      pdf = FileProxy.create(actor: @hans, title: "P", item_type: :transcript,
                             content: "x")
      assert_raises(ArgumentError) do
        KnowledgeItemBodyOps.new(pdf, actor: @hans).append_quote("   \n  ")
      end
    end
  end
end
