require "test_helper"

class WikilinkTypifyTest < ActiveSupport::TestCase
  setup do
    @hans = create_human
    grant(@hans, "KnowledgeItem", %w[read create update])
  end

  test "fuegt anchor in den Nten untyped Wikilink ein und legt Relation an" do
    with_isolated_miolimos_base do
      target = FileProxy.create(actor: @hans, title: "Ziel", item_type: :note, content: "")
      source = FileProxy.create(actor: @hans, title: "Quelle", item_type: :note,
                                 content: "Sieh mal [[Ziel]] dazu.")

      result = WikilinkTypify.call(actor: @hans, knowledge_item: source.reload,
                                    occurrence: 1)
      assert_not_nil result
      assert_match(/\A[0-9a-z]{6}\z/, result.anchor_id)
      assert_equal target.uuid, result.target_uuid
      assert_equal "Ziel", result.target_title

      source.reload
      assert_includes source.body, "^#{result.anchor_id}"
      rel = Relation.find_by!(source_uuid: source.uuid, anchor_id: result.anchor_id)
      assert_equal target.uuid, rel.target_uuid
    end
  end

  test "occurrence=2 typifiziert den zweiten Wikilink, erster bleibt untyped" do
    with_isolated_miolimos_base do
      FileProxy.create(actor: @hans, title: "A", item_type: :note, content: "")
      FileProxy.create(actor: @hans, title: "B", item_type: :note, content: "")
      source = FileProxy.create(actor: @hans, title: "Q", item_type: :note,
                                 content: "Erst [[A]], dann [[B]] noch [[A]].")

      result = WikilinkTypify.call(actor: @hans, knowledge_item: source.reload,
                                    occurrence: 2)
      source.reload
      assert_match(/\[\[A\]\]/, source.body, "erster A-Wikilink bleibt untyped")
      assert_match(/\[\[B\^#{result.anchor_id}\]\]/, source.body)
    end
  end

  test "Wikilink mit existierendem ^anchor wird nicht typified" do
    with_isolated_miolimos_base do
      target = FileProxy.create(actor: @hans, title: "Ziel", item_type: :note, content: "")
      source = FileProxy.create(actor: @hans, title: "Q", item_type: :note,
                                 content: "Sieh [[Ziel^abc123]] da.")

      result = WikilinkTypify.call(actor: @hans, knowledge_item: source.reload,
                                    occurrence: 1)
      assert_nil result, "no-op fuer schon getypten Wikilink"
    end
  end

  test "Wikilink mit unaufloesbarem Target liefert nil" do
    with_isolated_miolimos_base do
      source = FileProxy.create(actor: @hans, title: "Q", item_type: :note,
                                 content: "Sieh [[Gibts-nicht]] da.")
      result = WikilinkTypify.call(actor: @hans, knowledge_item: source.reload,
                                    occurrence: 1)
      assert_nil result
    end
  end

  test "occurrence ausserhalb des Bereichs liefert nil" do
    with_isolated_miolimos_base do
      FileProxy.create(actor: @hans, title: "Z", item_type: :note, content: "")
      source = FileProxy.create(actor: @hans, title: "Q", item_type: :note,
                                 content: "Nur [[Z]].")
      result = WikilinkTypify.call(actor: @hans, knowledge_item: source.reload,
                                    occurrence: 5)
      assert_nil result
    end
  end

  test "Wikilink mit Alias bleibt erhalten" do
    with_isolated_miolimos_base do
      FileProxy.create(actor: @hans, title: "Ziel", item_type: :note, content: "")
      source = FileProxy.create(actor: @hans, title: "Q", item_type: :note,
                                 content: "Sieh [[Ziel|kurz]].")
      result = WikilinkTypify.call(actor: @hans, knowledge_item: source.reload,
                                    occurrence: 1)
      source.reload
      assert_includes source.body, "[[Ziel^#{result.anchor_id}|kurz]]"
    end
  end
end
