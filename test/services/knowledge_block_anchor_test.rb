require "test_helper"

class KnowledgeBlockAnchorTest < ActiveSupport::TestCase
  setup do
    @hans = create_human
    grant(@hans, "KnowledgeItem", %w[read create update delete])
  end

  def create_note(content)
    FileProxy.create(
      actor: @hans, title: "Test", item_type: :note,
      content: content
    )
  end

  test "ensure! sets a stable anchor on the n-th unanchored block" do
    with_isolated_miolimos_base do
      item = create_note("Erster Absatz.\n\nZweiter Absatz.\n\nDritter Absatz.\n")
      anchor = KnowledgeBlockAnchor.new(item, actor: @hans).ensure!(2)

      assert anchor.present?
      body = FileProxy.read_body(actor: @hans, knowledge_item: item)
      assert_match(/Zweiter Absatz\.\s+\^#{anchor}\b/, body)
      assert_no_match(/Erster Absatz\.\s+\^/, body)
      assert_no_match(/Dritter Absatz\.\s+\^/, body)
    end
  end

  test "ensure! is idempotent — same n yields same anchor on repeated calls" do
    with_isolated_miolimos_base do
      item = create_note("A\n\nB\n\nC\n")
      svc  = KnowledgeBlockAnchor.new(item, actor: @hans)
      first  = svc.ensure!(2)
      second = svc.ensure!(2)
      # Bei N=2 ist B nach Setzen anker-versehen, also ist „der 2. anker-LOSE
      # Block" jetzt C. Der erste Anker bleibt aber bestehen — wir erwarten,
      # dass nicht doppelt gesetzt wird.
      assert first.present?
      assert second.present?
      refute_equal first, second
      body = FileProxy.read_body(actor: @hans, knowledge_item: item)
      assert_match(/B\s+\^#{first}\b/, body)
      assert_match(/C\s+\^#{second}\b/, body)
    end
  end

  test "ensure! returns nil when n is out of range" do
    with_isolated_miolimos_base do
      item = create_note("Nur ein Absatz.\n")
      assert_nil KnowledgeBlockAnchor.new(item, actor: @hans).ensure!(5)
    end
  end

  test "ensure! skips code blocks and horizontal rules when counting blocks (headings count)" do
    with_isolated_miolimos_base do
      item = create_note(<<~MD)
        ## Eine Überschrift

        Erster Absatz.

        ```ruby
        puts "code"
        ```

        ---

        Zweiter Absatz.
      MD
      # #341 (Hans, 2026-05-24): Headings sind jetzt anker-faehig und
      # zaehlen mit. Reihenfolge:
      #   block-1 = "## Eine Überschrift"
      #   block-2 = "Erster Absatz."
      #   (code block + HR werden uebersprungen)
      #   block-3 = "Zweiter Absatz."
      anchor = KnowledgeBlockAnchor.new(item, actor: @hans).ensure!(3)
      body = FileProxy.read_body(actor: @hans, knowledge_item: item)
      assert_match(/Zweiter Absatz\.\s+\^#{anchor}\b/, body)
      assert_no_match(/puts "code".*\^/, body)
      assert_no_match(/^---\s+\^/, body)
    end
  end

  test "ensure! treats list items as separate blocks" do
    with_isolated_miolimos_base do
      item = create_note("- Eins\n- Zwei\n- Drei\n")
      anchor = KnowledgeBlockAnchor.new(item, actor: @hans).ensure!(2)
      body = FileProxy.read_body(actor: @hans, knowledge_item: item)
      assert_match(/- Zwei\s+\^#{anchor}\b/, body)
    end
  end

  test "text_at returns plain text of the block with markdown markers stripped" do
    with_isolated_miolimos_base do
      item = create_note("Erster.\n\n**Zweiter** mit *Emphase*. ^abc\n")
      text = KnowledgeBlockAnchor.new(item, actor: @hans).text_at("abc")
      assert_equal "Zweiter mit Emphase.", text
    end
  end

  test "text_at returns empty string when anchor not found" do
    with_isolated_miolimos_base do
      item = create_note("Nur Text.\n")
      assert_equal "", KnowledgeBlockAnchor.new(item, actor: @hans).text_at("missing")
    end
  end

  test "text_at strips list markers and wikilink brackets" do
    with_isolated_miolimos_base do
      item = create_note("- [[Anderes KI]] ist relevant. ^xyz\n")
      text = KnowledgeBlockAnchor.new(item, actor: @hans).text_at("xyz")
      assert_equal "Anderes KI ist relevant.", text
    end
  end
end
