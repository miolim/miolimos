require "test_helper"

# #592 Z2: Fokusansicht — lokaler Ausschnitt um einen Baum-Knoten.
class TreeFocusControllerTest < ActionDispatch::IntegrationTest
  setup do
    @hans = HumanActor.create!(name: "Hans", email: "hans-tf-#{SecureRandom.hex(3)}@t.local",
                               password: "secretsecret")
    grant(@hans, "KnowledgeItem", %w[read create update])
    grant(@hans, "Topic", %w[read create update])
    grant(@hans, "Task", %w[read])   # Dashboard-Restore-Test
    @topic = Topic.create!(slug: "tf-topic-#{SecureRandom.hex(3)}", name: "TF-Topic", creator: @hans)
    @tree  = @topic.topic_trees.create!(kind: "purpose", position: 1)
    post "/login", params: { email: @hans.email, password: "secretsecret" }
  end

  def ki(title) = FileProxy.create(actor: @hans, title: title, item_type: :note, content: "")
  def node(title, parent: nil, junctor: nil, chosen: false)
    n = WorkNodeOps.create(topic: @topic, knowledge_item: ki(title), parent: parent, tree: @tree)
    WorkNodeOps.update_junctor(n, junctor) if junctor
    n.update!(chosen: true) if chosen
    n
  end

  test "Wurzelzustand: Verfeinerungs-Kasten + Wie?, kein Kontext/Warum" do
    with_isolated_miolimos_base do
      root = node("Wurzelzweck", junctor: "and")
      node("Teil A", parent: root)
      get "/tree_focus/#{root.id}/card"
      assert_response :success
      assert_includes @response.body, "Wurzelzweck"
      assert_includes @response.body, "↓ Wie?"
      refute_includes @response.body, "↑ Warum?"
      assert_includes @response.body, "alle nötig"
      assert_includes @response.body, "treefocus:#{root.id}"
    end
  end

  test "Fokus auf ODER-Kind: Kontext-Kasten dimmt Geschwister, IST sichtbar" do
    with_isolated_miolimos_base do
      root = node("Wurzel", junctor: "or")
      a = node("Alternative A", parent: root, chosen: true)
      node("Alternative B", parent: root)
      get "/tree_focus/#{root.id}/card", params: { focus: a.id }
      assert_response :success
      assert_includes @response.body, "↑ Warum?"
      assert_includes @response.body, "eine genügt"
      assert_includes @response.body, "oder"                       # ODER-Trenner
      assert_includes @response.body, "Keine weitere Verfeinerung"  # A ist Blatt
      assert_includes @response.body, "Ebene 2"
    end
  end

  test "geteiltes Element zeigt Sprung-Verweis zum nächsten Vorkommen" do
    with_isolated_miolimos_base do
      root   = node("Wurzel", junctor: "and")
      links  = node("Links", parent: root, junctor: "and")
      rechts = node("Rechts", parent: root, junctor: "and")
      shared = ki("Plausi")
      WorkNodeOps.create(topic: @topic, knowledge_item: shared, parent: links)
      n2 = WorkNodeOps.create(topic: @topic, knowledge_item: shared, parent: rechts)
      first_occ = @tree.nodes.where(knowledge_item_uuid: shared.uuid).order(:id).first
      get "/tree_focus/#{first_occ.id}/card", params: { focus: first_occ.id }
      assert_response :success
      assert_includes @response.body, "auch unter"
      assert_includes @response.body, "focus=#{n2.id}"
    end
  end

  test "Stack-Restore: treefocus-Token rendert das Blade" do
    with_isolated_miolimos_base do
      root = node("Restore-Zweck")
      get "/dashboard", params: { stack: "treefocus:#{root.id}" }
      assert_response :success
      assert_includes @response.body, "stack_card_treefocus:#{root.id}"
      assert_includes @response.body, "Restore-Zweck"
    end
  end
end
