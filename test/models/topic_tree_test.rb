require "test_helper"

# #592: Verallgemeinerte Topic-Bäume — Work-Tree als Sonderfall,
# Zweckgeflecht (kind=purpose) mit Junktor + IST-Markierung.
class TopicTreeTest < ActiveSupport::TestCase
  setup do
    @hans  = create_human
    grant(@hans, "KnowledgeItem", %w[read create update])
    grant(@hans, "Topic", %w[read create update])
    @topic = Topic.create!(name: "Baum-Topic", slug: "bt-#{SecureRandom.hex(3)}", creator: @hans)
    @ki    = FileProxy.create(actor: @hans, title: "Item-KI #{SecureRandom.hex(3)}",
                              item_type: :note, content: "Inhalt.")
  end

  test "Direkterzeugung ohne tree landet im Default-Work-Tree (Alt-Verhalten)" do
    n = WorkNode.create!(topic: @topic, knowledge_item_uuid: @ki.uuid, role: "content", position: 1)
    assert_equal "work", n.tree.kind
    assert_equal n.tree, @topic.default_work_tree
    assert_includes @topic.work_tree_roots, n
  end

  test "Geschwister-Positionen sind je Baum isoliert (mehrere Bäume möglich)" do
    werk    = @topic.default_work_tree
    purpose = @topic.topic_trees.create!(kind: "purpose", name: "Zweckgeflecht", position: 2)
    a = WorkNodeOps.create(topic: @topic, knowledge_item: @ki, tree: werk)
    b = WorkNodeOps.create(topic: @topic, knowledge_item: @ki, tree: purpose)
    assert_equal 1, a.position
    assert_equal 1, b.position, "Positionen dürfen sich nicht über Bäume hinweg hochzählen"
    assert_equal [a], werk.roots.to_a
    assert_equal [b], purpose.roots.to_a
  end

  test "Junktor setzen + IST-Wahl ist exklusiv je ODER-Verzweigung" do
    purpose = @topic.topic_trees.create!(kind: "purpose", position: 2)
    parent  = WorkNodeOps.create(topic: @topic, knowledge_item: @ki, tree: purpose)
    WorkNodeOps.update_junctor(parent, "or")
    assert_equal "or", parent.reload.junctor

    k1 = WorkNodeOps.create(topic: @topic, knowledge_item: @ki, parent: parent)
    k2 = WorkNodeOps.create(topic: @topic, knowledge_item: @ki, parent: parent)
    WorkNodeOps.choose(k1)
    assert k1.reload.chosen
    WorkNodeOps.choose(k2)
    assert k2.reload.chosen
    refute k1.reload.chosen, "Wahl muss exklusiv unter Geschwistern sein"
  end

  test "Reparent über Baumgrenzen wird abgelehnt" do
    werk    = @topic.default_work_tree
    purpose = @topic.topic_trees.create!(kind: "purpose", position: 2)
    a = WorkNodeOps.create(topic: @topic, knowledge_item: @ki, tree: werk)
    b = WorkNodeOps.create(topic: @topic, knowledge_item: @ki, tree: purpose)
    assert_raises(WorkNodeOps::Error) { WorkNodeOps.reparent(b, a) }
  end
end
