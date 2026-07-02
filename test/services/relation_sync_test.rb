require "test_helper"

class RelationSyncTest < ActiveSupport::TestCase
  setup do
    @hans   = create_human
    grant(@hans, "KnowledgeItem", %w[read create update])
    @target = KnowledgeItem.create!(uuid: SecureRandom.uuid, title: "Ziel-Notiz",
                                     item_type: :note, file_path: "x/ziel.md",
                                     content_hash: "h", body: "Inhalt")
    @source = KnowledgeItem.create!(uuid: SecureRandom.uuid, title: "Quelle",
                                     item_type: :note, file_path: "x/quelle.md",
                                     content_hash: "h", body: "")
  end

  test "legt Relation an fuer Wikilink mit anchor_id" do
    @source.update!(body: "Sieh mal [[Ziel-Notiz ^abc123]] dazu.")
    RelationSync.sync(@source, @source.body)
    rel = Relation.find_by!(source_uuid: @source.uuid, anchor_id: "abc123")
    assert_equal @target.uuid, rel.target_uuid
    assert_equal "KnowledgeItem", rel.target_type
    assert_nil rel.orphaned_at
  end

  test "ignoriert Wikilinks ohne anchor_id" do
    @source.update!(body: "[[Ziel-Notiz]] — kein anchor.")
    RelationSync.sync(@source, @source.body)
    assert_equal 0, Relation.for_source(@source.uuid).count
  end

  test "dangling target: behaelt target-string als Pseudo-UUID" do
    @source.update!(body: "Sieh [[Gibt-es-nicht ^def456]] an.")
    RelationSync.sync(@source, @source.body)
    rel = Relation.find_by!(source_uuid: @source.uuid, anchor_id: "def456")
    assert_equal "Gibt-es-nicht", rel.target_uuid
  end

  test "anchor_id, der nicht mehr im Body steht: orphaned_at gesetzt" do
    @source.update!(body: "[[Ziel-Notiz ^abc123]]")
    RelationSync.sync(@source, @source.body)
    rel = Relation.find_by!(source_uuid: @source.uuid, anchor_id: "abc123")
    assert_nil rel.orphaned_at

    # Body ohne den anchor
    @source.update!(body: "Etwas anderes.")
    RelationSync.sync(@source, @source.body)
    rel.reload
    refute_nil rel.orphaned_at
  end

  test "generate_anchor_id liefert 6-Zeichen base36" do
    id = Relation.generate_anchor_id(source_uuid: SecureRandom.uuid)
    assert_match(/\A[0-9a-z]{6}\z/, id)
  end

  test "Update auf existierende Relation aendert orphaned_at nicht zurueck wenn anchor wieder auftaucht" do
    @source.update!(body: "[[Ziel-Notiz ^abc123]]")
    RelationSync.sync(@source, @source.body)
    rel = Relation.find_by!(source_uuid: @source.uuid, anchor_id: "abc123")
    rel.update!(label: "loest aus", description: "Mein Kommentar.")

    @source.update!(body: "anderer text")
    RelationSync.sync(@source, @source.body)
    rel.reload
    refute_nil rel.orphaned_at
    assert_equal "loest aus", rel.label, "label bleibt erhalten"

    # Anchor taucht wieder im Body auf
    @source.update!(body: "[[Ziel-Notiz ^abc123]] wieder da.")
    RelationSync.sync(@source, @source.body)
    rel.reload
    assert_nil rel.orphaned_at, "wieder aktiv"
    assert_equal "loest aus", rel.label
  end
end
