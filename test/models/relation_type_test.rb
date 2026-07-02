require "test_helper"

class RelationTypeTest < ActiveSupport::TestCase
  test "name required + unique case-insensitive" do
    RelationType.create!(name: "Löst aus")
    rt = RelationType.new(name: "löst aus")
    refute rt.valid?
    assert_match(/already been taken|bereits/i, rt.errors.full_messages.join)
  end

  test "find_by_label matched case-insensitive" do
    rt = RelationType.create!(name: "Löst aus", inverse_name: "Wird ausgelöst von")
    assert_equal rt, RelationType.find_by_label("löst aus")
    assert_equal rt, RelationType.find_by_label(" LÖST AUS ".strip)
    assert_nil RelationType.find_by_label("nicht da")
    assert_nil RelationType.find_by_label("")
    assert_nil RelationType.find_by_label(nil)
  end

  test "ebene wird auf Inclusion-List validiert + leerstring normalisiert auf nil" do
    rt = RelationType.create!(name: "sozial-test", ebene: "sozial")
    assert_equal "sozial", rt.ebene

    rt.ebene = "  POLITISCH  "
    rt.save!
    assert_equal "politisch", rt.ebene

    rt.ebene = ""
    rt.save!
    assert_nil rt.ebene

    rt.ebene = "nicht-erlaubt"
    refute rt.valid?
  end

  test "Relation.ROLES enthaelt user_confirmed (#155 Phase 5a)" do
    assert_includes Relation::ROLES, "user_confirmed"
  end

  test "usage_count zaehlt Relations mit gleichem Label" do
    rt = RelationType.create!(name: "blockiert")
    src = KnowledgeItem.create!(uuid: SecureRandom.uuid, title: "S",
                                 item_type: :note, file_path: "s-#{SecureRandom.hex(3)}.md",
                                 content_hash: "h", body: "")
    tgt = KnowledgeItem.create!(uuid: SecureRandom.uuid, title: "T",
                                 item_type: :note, file_path: "t-#{SecureRandom.hex(3)}.md",
                                 content_hash: "h", body: "")
    Relation.create!(source_uuid: src.uuid, source_type: "KnowledgeItem",
                     target_uuid: tgt.uuid, target_type: "KnowledgeItem",
                     anchor_id: "aaa111", label: "blockiert")
    Relation.create!(source_uuid: src.uuid, source_type: "KnowledgeItem",
                     target_uuid: tgt.uuid, target_type: "KnowledgeItem",
                     anchor_id: "bbb222", label: "Blockiert")
    Relation.create!(source_uuid: src.uuid, source_type: "KnowledgeItem",
                     target_uuid: tgt.uuid, target_type: "KnowledgeItem",
                     anchor_id: "ccc333", label: "anderes")
    assert_equal 2, rt.usage_count
  end
end
