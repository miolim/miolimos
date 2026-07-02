require "test_helper"

# #378 Phase 5 (Hans, 2026-05-26): Tests fuer WorkNode — der
# Tree-Knoten aus #325, bisher nur indirekt ueber Service-Tests
# abgedeckt.
class WorkNodeTest < ActiveSupport::TestCase
  setup do
    @hans = create_human
    grant(@hans, "KnowledgeItem", %w[read create update delete])
    grant(@hans, "Topic", %w[read create update])
    @topic = Topic.create!(slug: "work-node-topic-#{SecureRandom.hex(3)}",
                            name: "Topic", creator: @hans)
    @ki = FileProxy.create(actor: @hans, title: "KI", item_type: :note, content: "x")
  end

  test "valid WorkNode persists" do
    node = WorkNode.create!(topic: @topic, knowledge_item: @ki, role: "heading", position: 1)
    assert node.persisted?
  end

  test "rejects unknown role" do
    node = WorkNode.new(topic: @topic, knowledge_item: @ki, role: "bogus", position: 1)
    assert_not node.valid?
    assert node.errors[:role].any?
  end

  test "accepts both heading and content roles" do
    %w[heading content].each_with_index do |role, i|
      n = WorkNode.create!(topic: @topic, knowledge_item: @ki, role: role, position: i)
      assert n.persisted?
    end
  end

  test "requires integer position" do
    node = WorkNode.new(topic: @topic, knowledge_item: @ki, role: "heading", position: 1.5)
    assert_not node.valid?
    assert node.errors[:position].any?
  end

  test "parent must belong to same topic" do
    other_topic = Topic.create!(slug: "other-#{SecureRandom.hex(3)}", name: "O",
                                 creator: @hans)
    parent = WorkNode.create!(topic: other_topic, knowledge_item: @ki,
                                role: "heading", position: 1)
    child = WorkNode.new(topic: @topic, parent: parent, knowledge_item: @ki,
                          role: "content", position: 1)
    assert_not child.valid?
    assert_match(/gleichen Topic/, child.errors[:parent].first.to_s)
  end

  test "parent in same topic is allowed" do
    parent = WorkNode.create!(topic: @topic, knowledge_item: @ki, role: "heading", position: 1)
    child = WorkNode.create!(topic: @topic, parent: parent, knowledge_item: @ki,
                              role: "content", position: 1)
    assert child.persisted?
  end

  test "children scope returns ordered by position" do
    parent = WorkNode.create!(topic: @topic, knowledge_item: @ki, role: "heading", position: 1)
    c3 = WorkNode.create!(topic: @topic, parent: parent, knowledge_item: @ki, role: "content", position: 3)
    c1 = WorkNode.create!(topic: @topic, parent: parent, knowledge_item: @ki, role: "content", position: 1)
    c2 = WorkNode.create!(topic: @topic, parent: parent, knowledge_item: @ki, role: "content", position: 2)
    assert_equal [c1, c2, c3], parent.children.to_a
  end

  test "roots scope returns only parentless nodes" do
    root = WorkNode.create!(topic: @topic, knowledge_item: @ki, role: "heading", position: 1)
    WorkNode.create!(topic: @topic, parent: root, knowledge_item: @ki, role: "content", position: 1)
    roots = WorkNode.where(topic: @topic).roots.to_a
    assert_equal [root], roots
  end

  test "destroying parent cascades to children" do
    parent = WorkNode.create!(topic: @topic, knowledge_item: @ki, role: "heading", position: 1)
    WorkNode.create!(topic: @topic, parent: parent, knowledge_item: @ki, role: "content", position: 1)
    assert_difference -> { WorkNode.where(topic: @topic).count }, -2 do
      parent.destroy!
    end
  end
end
