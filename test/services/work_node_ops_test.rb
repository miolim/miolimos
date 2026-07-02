require "test_helper"

# #378 (Hans, 2026-05-26): Tests fuer WorkNodeOps — CRUD-Operations
# am Work-Tree (#325).
class WorkNodeOpsTest < ActiveSupport::TestCase
  setup do
    @hans = create_human
    grant(@hans, "KnowledgeItem", %w[read create update delete])
    grant(@hans, "Topic", %w[read create update delete])
  end

  def create_ki(title)
    FileProxy.create(actor: @hans, title: title, item_type: :note, content: "")
  end

  def make_topic
    Topic.create!(name: "T", slug: "t-#{SecureRandom.hex(4)}", creator: @hans)
  end

  test "create appends a new node at the end of root siblings" do
    with_isolated_miolimos_base do
      topic = make_topic
      ki1 = create_ki("A")
      ki2 = create_ki("B")

      n1 = WorkNodeOps.create(topic: topic, knowledge_item: ki1, role: "heading")
      n2 = WorkNodeOps.create(topic: topic, knowledge_item: ki2, role: "content")

      assert_equal 1, n1.position
      assert_equal 2, n2.position
      assert_nil n1.parent_id
    end
  end

  test "create auto-links KI to topic (ensure_material!)" do
    with_isolated_miolimos_base do
      topic = make_topic
      ki = create_ki("X")
      WorkNodeOps.create(topic: topic, knowledge_item: ki, role: "content")
      assert_includes topic.knowledge_items.pluck(:uuid), ki.uuid
    end
  end

  test "indent makes node a child of the previous sibling" do
    with_isolated_miolimos_base do
      topic = make_topic
      a = WorkNodeOps.create(topic: topic, knowledge_item: create_ki("A"), role: "heading")
      b = WorkNodeOps.create(topic: topic, knowledge_item: create_ki("B"), role: "content")

      WorkNodeOps.indent(b)
      b.reload
      assert_equal a.id, b.parent_id
    end
  end

  test "indent raises when no previous sibling" do
    with_isolated_miolimos_base do
      topic = make_topic
      only = WorkNodeOps.create(topic: topic, knowledge_item: create_ki("X"), role: "heading")
      assert_raises(WorkNodeOps::Error) { WorkNodeOps.indent(only) }
    end
  end

  test "outdent makes node a sibling of its parent" do
    with_isolated_miolimos_base do
      topic = make_topic
      a = WorkNodeOps.create(topic: topic, knowledge_item: create_ki("A"), role: "heading")
      b = WorkNodeOps.create(topic: topic, knowledge_item: create_ki("B"), role: "content")
      WorkNodeOps.indent(b)
      b.reload

      WorkNodeOps.outdent(b)
      b.reload
      assert_nil b.parent_id
    end
  end

  test "outdent raises when node is already top-level" do
    with_isolated_miolimos_base do
      topic = make_topic
      n = WorkNodeOps.create(topic: topic, knowledge_item: create_ki("X"), role: "heading")
      assert_raises(WorkNodeOps::Error) { WorkNodeOps.outdent(n) }
    end
  end

  test "update_role flips heading <-> content" do
    with_isolated_miolimos_base do
      topic = make_topic
      n = WorkNodeOps.create(topic: topic, knowledge_item: create_ki("X"), role: "heading")
      WorkNodeOps.update_role(n, "content")
      assert_equal "content", n.reload.role
    end
  end

  test "update_role rejects invalid role" do
    with_isolated_miolimos_base do
      topic = make_topic
      n = WorkNodeOps.create(topic: topic, knowledge_item: create_ki("X"), role: "heading")
      assert_raises(WorkNodeOps::Error) { WorkNodeOps.update_role(n, "bogus") }
    end
  end

  test "reorder re-indexes siblings consistently" do
    with_isolated_miolimos_base do
      topic = make_topic
      a = WorkNodeOps.create(topic: topic, knowledge_item: create_ki("A"), role: "heading")
      b = WorkNodeOps.create(topic: topic, knowledge_item: create_ki("B"), role: "heading")
      c = WorkNodeOps.create(topic: topic, knowledge_item: create_ki("C"), role: "heading")

      WorkNodeOps.reorder(c, 1)
      assert_equal [c.id, a.id, b.id], topic.work_nodes.where(parent_id: nil).order(:position).pluck(:id)
    end
  end

  test "reparent moves node under new_parent and re-indexes" do
    with_isolated_miolimos_base do
      topic = make_topic
      a = WorkNodeOps.create(topic: topic, knowledge_item: create_ki("A"), role: "heading")
      b = WorkNodeOps.create(topic: topic, knowledge_item: create_ki("B"), role: "heading")
      c = WorkNodeOps.create(topic: topic, knowledge_item: create_ki("C"), role: "heading")

      WorkNodeOps.reparent(c, a)
      assert_equal a.id, c.reload.parent_id
      # b sollte jetzt position 2 sein (von 3 vorher; a=1, c war 3, jetzt unter a)
      assert_equal [a.id, b.id], topic.work_nodes.where(parent_id: nil).order(:position).pluck(:id)
    end
  end

  test "reparent raises on cycle" do
    with_isolated_miolimos_base do
      topic = make_topic
      parent = WorkNodeOps.create(topic: topic, knowledge_item: create_ki("P"), role: "heading")
      child  = WorkNodeOps.create(topic: topic, knowledge_item: create_ki("C"), role: "content")
      WorkNodeOps.reparent(child, parent)
      assert_raises(WorkNodeOps::Error) { WorkNodeOps.reparent(parent, child) }
    end
  end

  test "remove deletes node and descendants but keeps the KI" do
    with_isolated_miolimos_base do
      topic = make_topic
      ki = create_ki("X")
      n = WorkNodeOps.create(topic: topic, knowledge_item: ki, role: "heading")
      WorkNodeOps.remove(n)
      assert_nil WorkNode.find_by(id: n.id)
      assert KnowledgeItem.find_by(uuid: ki.uuid), "KI sollte bleiben"
    end
  end
end
