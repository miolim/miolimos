require "test_helper"

# #378 Phase 6 (Hans, 2026-05-26): Tests fuer WorkNodesController
# (108 LoC, bisher ungetestet). #325-Work-Tree-CRUD.
class WorkNodesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @hans = HumanActor.create!(
      name: "Hans", email: "hans-wn-#{SecureRandom.hex(3)}@t.local",
      password: "secretsecret"
    )
    grant(@hans, "KnowledgeItem", %w[read create update delete])
    grant(@hans, "Topic", %w[read create update delete])
    @topic = Topic.create!(slug: "wn-topic-#{SecureRandom.hex(3)}",
                            name: "WN-Topic", creator: @hans)
    @ki = FileProxy.create(actor: @hans, title: "WN-KI", item_type: :note, content: "x")
    post "/login", params: { email: @hans.email, password: "secretsecret" }
  end

  # #740 (Hans): Arten-Unterscheidung aufgehoben — jeder Baum (auch ein
  # reiner Mittel-Zweck/purpose-Baum ohne Werk-Baum) ist renderbar.
  # work_tree_roots fällt auf den ersten Baum mit Knoten zurück, has_tree?
  # ist kind-agnostisch. Vorher: purpose-only-Topic = leeres Render, kein Button.
  test "#740 Mittel-Zweck-only-Topic ist renderbar (has_tree? + work_tree_roots-Fallback)" do
    with_isolated_miolimos_base do
      tree = @topic.topic_trees.create!(kind: "purpose", position: 1)
      WorkNodeOps.create(topic: @topic, knowledge_item: @ki, tree: tree)
      assert @topic.topic_trees.work.empty?, "Setup: es gibt KEINEN Werk-Baum"
      assert @topic.reload.has_tree?, "Topic mit Baum-Knoten → has_tree? true"
      refute @topic.work_tree_roots.empty?, "work_tree_roots fällt auf den Mittel-Zweck-Baum zurück"
    end
  end

  # ── #592: Zweckgeflecht (purpose-Baum) ─────────────────────────────
  test "POST mit tree_kind=purpose + title legt Stub-KI und purpose-Knoten an" do
    with_isolated_miolimos_base do
      assert_difference -> { KnowledgeItem.where(item_type: "note").count }, 1 do
        post "/topics/#{@topic.slug}/work_nodes",
             params: { tree_kind: "purpose", title: "Lohnabrechnung sicherstellen" },
             headers: { "Accept" => "text/vnd.turbo-stream.html" }
      end
      assert_response :success
      tree = @topic.topic_trees.purpose.first
      assert tree, "purpose-Baum sollte lazy entstehen"
      node = tree.roots.first
      assert_equal "Lohnabrechnung sicherstellen", node.knowledge_item.title
      # Work-Tree bleibt unberührt
      assert_equal 0, @topic.work_nodes.joins(:tree).where(topic_trees: { kind: "work" }).count
    end
  end

  test "POST mit Titel einer BESTEHENDEN KI verknüpft sie statt Stub anzulegen" do
    with_isolated_miolimos_base do
      assert_no_difference -> { KnowledgeItem.count } do
        post "/topics/#{@topic.slug}/work_nodes",
             params: { tree_kind: "purpose", title: @ki.title.upcase },
             headers: { "Accept" => "text/vnd.turbo-stream.html" }
      end
      assert_response :success
      node = @topic.topic_trees.purpose.first.roots.first
      assert_equal @ki.uuid, node.knowledge_item_uuid
    end
  end

  test "Stub-KIs tragen das Tag zweckgeflecht (Trennung/Filterbarkeit)" do
    with_isolated_miolimos_base do
      post "/topics/#{@topic.slug}/work_nodes",
           params: { tree_kind: "purpose", title: "Frische-Stub-#{SecureRandom.hex(2)}" },
           headers: { "Accept" => "text/vnd.turbo-stream.html" }
      stub = @topic.topic_trees.purpose.first.roots.first.knowledge_item
      assert_includes Array(stub.tags), "zweckgeflecht"
    end
  end

  test "PATCH junctor + chosen (exklusiv) am purpose-Knoten" do
    with_isolated_miolimos_base do
      tree   = @topic.topic_trees.create!(kind: "purpose", position: 2)
      parent = WorkNodeOps.create(topic: @topic, knowledge_item: @ki, tree: tree)
      k1     = WorkNodeOps.create(topic: @topic, knowledge_item: @ki, parent: parent)
      k2     = WorkNodeOps.create(topic: @topic, knowledge_item: @ki, parent: parent)

      patch "/topics/#{@topic.slug}/work_nodes/#{parent.id}",
            params: { junctor: "or" }, headers: { "Accept" => "text/vnd.turbo-stream.html" }
      assert_response :success
      assert_equal "or", parent.reload.junctor

      patch "/topics/#{@topic.slug}/work_nodes/#{k1.id}",
            params: { chosen: "1" }, headers: { "Accept" => "text/vnd.turbo-stream.html" }
      patch "/topics/#{@topic.slug}/work_nodes/#{k2.id}",
            params: { chosen: "1" }, headers: { "Accept" => "text/vnd.turbo-stream.html" }
      assert k2.reload.chosen
      refute k1.reload.chosen, "IST-Wahl muss exklusiv sein"
    end
  end

  test "Gliederungen-Reiter rendert Junktor-Badge und IST-Punkt" do
    with_isolated_miolimos_base do
      tree   = @topic.topic_trees.create!(kind: "purpose", name: "Zweckgeflecht", position: 2)
      parent = WorkNodeOps.create(topic: @topic, knowledge_item: @ki, tree: tree)
      WorkNodeOps.update_junctor(parent, "or")
      kind = FileProxy.create(actor: @hans, title: "Alternative A", item_type: :note, content: "x")
      child = WorkNodeOps.create(topic: @topic, knowledge_item: kind, parent: parent)
      WorkNodeOps.choose(child)

      get "/topics/#{@topic.slug}/list_card", params: { tab: "trees", tree_id: tree.id }
      assert_response :success
      assert_includes @response.body, "Gliederungen"
      assert_includes @response.body, ">ODER<"        # Junktor-Badge am Eltern
      assert_includes @response.body, "Alternative A"
      assert_includes @response.body, "IST-Markierung entfernen"  # gewählter IST-Punkt
    end
  end

  # ── #592 Linsen-Modell ───────────────────────────────────────────
  test "Reiter zeigen jeden Baum via tree_id (Linse), Picker listet Bäume" do
    with_isolated_miolimos_base do
      werk = @topic.default_work_tree
      WorkNodeOps.create(topic: @topic, knowledge_item: @ki, tree: werk)
      zweck = @topic.topic_trees.create!(kind: "purpose", name: "Analyse", position: 2)
      andere = FileProxy.create(actor: @hans, title: "Zweck-Wurzel", item_type: :note, content: "x")
      WorkNodeOps.create(topic: @topic, knowledge_item: andere, tree: zweck)

      # Gliederungen-Reiter (alter Key "zweck" aliast) auf den WORK-Baum
      get "/topics/#{@topic.slug}/list_card", params: { tab: "zweck", tree_id: werk.id }
      assert_response :success
      assert_includes @response.body, "Gliederungen"
      assert_includes @response.body, @ki.title
      # genau EIN Knoten gerendert (der des Work-Baums)
      assert_equal 1, @response.body.scan(/id="work_node_/).size
      refute_match %r{id="work_node_#{@topic.topic_trees.purpose.first.roots.first.id}"}, @response.body
      # Picker zeigt beide Bäume
      assert_includes @response.body, "Analyse"
      assert_includes @response.body, "+ Baum"
    end
  end

  # #592-Fix (Hans-Report): Topic mit NUR einem purpose-Baum zeigte im
  # Gliederungen-Reiter Zähler, aber keinen Inhalt (Fallback war work-only).
  test "Gliederungen-Reiter zeigt den purpose-Baum auch ohne work-Baum" do
    with_isolated_miolimos_base do
      tree = @topic.topic_trees.create!(kind: "purpose", position: 1)
      WorkNodeOps.create(topic: @topic, knowledge_item: @ki, tree: tree)
      get "/topics/#{@topic.slug}/list_card", params: { tab: "trees" }
      assert_response :success
      assert_includes @response.body, @ki.title
      assert_equal 1, @response.body.scan(/id="work_node_/).size
    end
  end

  # #599: Inhalt-Toggle im Wissen-Reiter (Alle | Nur Titel | Mit Inhalt).
  test "Wissen-Reiter rendert Inhalt-Toggle und data-has-body an den Zeilen" do
    with_isolated_miolimos_base do
      mit  = FileProxy.create(actor: @hans, title: "Mit-Inhalt", item_type: :note, content: "Text da.")
      ohne = FileProxy.create(actor: @hans, title: "Ohne-Inhalt", item_type: :note, content: "")
      @topic.knowledge_item_topics.create!(knowledge_item: mit)
      @topic.knowledge_item_topics.create!(knowledge_item: ohne)
      get "/topics/#{@topic.slug}/list_card", params: { tab: "knowledge" }
      assert_response :success
      assert_includes @response.body, "Nur Titel"
      assert_includes @response.body, "Mit Inhalt"
      assert_includes @response.body, "content-filter#filter"
      assert_match %r{knowledge_row_#{mit.uuid}"\s+data-has-body="true"}, @response.body
      assert_match %r{knowledge_row_#{ohne.uuid}"\s+data-has-body="false"}, @response.body
    end
  end

  # #600: Gliederung löschen — Knoten kaskadieren, KIs bleiben.
  test "DELETE /trees/:id entfernt Baum + Knoten, KIs bleiben" do
    with_isolated_miolimos_base do
      tree = @topic.topic_trees.create!(kind: "purpose", position: 1)
      WorkNodeOps.create(topic: @topic, knowledge_item: @ki, tree: tree)
      assert_difference -> { @topic.topic_trees.count } => -1, -> { WorkNode.count } => -1,
                        -> { KnowledgeItem.count } => 0 do
        delete "/topics/#{@topic.slug}/trees/#{tree.id}",
               headers: { "Accept" => "text/vnd.turbo-stream.html" }
      end
      assert_response :success
    end
  end

  test "POST /trees legt weiteren Baum an" do
    with_isolated_miolimos_base do
      assert_difference -> { @topic.topic_trees.count }, 1 do
        post "/topics/#{@topic.slug}/trees",
             params: { kind: "purpose", name: "Variante B", tab: "zweck" },
             headers: { "Accept" => "text/vnd.turbo-stream.html" }
      end
      assert_response :success
      assert_equal "Variante B", @topic.topic_trees.purpose.last.name
    end
  end

  test "Render-Blade zeigt ODER-Verzweigung als Alternativen-Liste mit IST" do
    with_isolated_miolimos_base do
      werk   = @topic.default_work_tree
      parent = WorkNodeOps.create(topic: @topic, knowledge_item: @ki, tree: werk, role: "heading")
      WorkNodeOps.update_junctor(parent, "or")
      a = FileProxy.create(actor: @hans, title: "Alternative-Alpha", item_type: :note, content: "Inhalt Alpha")
      b = FileProxy.create(actor: @hans, title: "Alternative-Beta",  item_type: :note, content: "Inhalt Beta")
      na = WorkNodeOps.create(topic: @topic, knowledge_item: a, parent: parent)
      WorkNodeOps.create(topic: @topic, knowledge_item: b, parent: parent)
      WorkNodeOps.choose(na)

      get "/topics/#{@topic.slug}/render_card"
      assert_response :success
      assert_includes @response.body, "Alternativen — eine genügt"
      assert_includes @response.body, "Alternative-Alpha — IST"
      assert_includes @response.body, "Inhalt Alpha"          # gewählter Ast voll gerendert
      refute_includes @response.body, "Inhalt Beta"           # verdeckte Alternative nur als Listenzeile
      assert_includes @response.body, "Alternative-Beta"
    end
  end

  test "POST work_nodes creates a WorkNode and responds with turbo-stream" do
    with_isolated_miolimos_base do
      assert_difference -> { WorkNode.where(topic: @topic).count }, 1 do
        post "/topics/#{@topic.slug}/work_nodes",
             params: { knowledge_item_uuid: @ki.uuid, role: "content" },
             headers: { "Accept" => "text/vnd.turbo-stream.html" }
      end
      assert_response :success
    end
  end

  test "POST work_nodes places under given parent" do
    with_isolated_miolimos_base do
      parent = WorkNode.create!(topic: @topic, knowledge_item: @ki,
                                  role: "heading", position: 1)
      post "/topics/#{@topic.slug}/work_nodes",
           params: { knowledge_item_uuid: @ki.uuid, parent_id: parent.id,
                     role: "content" },
           headers: { "Accept" => "text/vnd.turbo-stream.html" }
      assert_response :success
      child = WorkNode.where(topic: @topic, parent: parent).first
      assert child, "child node should exist under parent"
    end
  end

  test "PATCH work_node updates role" do
    with_isolated_miolimos_base do
      node = WorkNode.create!(topic: @topic, knowledge_item: @ki,
                                role: "content", position: 1)
      patch "/topics/#{@topic.slug}/work_nodes/#{node.id}",
            params: { role: "heading" },
            headers: { "Accept" => "text/vnd.turbo-stream.html" }
      assert_response :success
      assert_equal "heading", node.reload.role
    end
  end

  test "DELETE work_node removes it" do
    with_isolated_miolimos_base do
      node = WorkNode.create!(topic: @topic, knowledge_item: @ki,
                                role: "content", position: 1)
      assert_difference -> { WorkNode.where(topic: @topic).count }, -1 do
        delete "/topics/#{@topic.slug}/work_nodes/#{node.id}",
               headers: { "Accept" => "text/vnd.turbo-stream.html" }
      end
      assert_response :success
    end
  end

  test "POST indent demotes node under its previous sibling" do
    with_isolated_miolimos_base do
      first  = WorkNode.create!(topic: @topic, knowledge_item: @ki,
                                  role: "content", position: 1)
      second = WorkNode.create!(topic: @topic, knowledge_item: @ki,
                                  role: "content", position: 2)
      post "/topics/#{@topic.slug}/work_nodes/#{second.id}/indent",
           headers: { "Accept" => "text/vnd.turbo-stream.html" }
      assert_response :success
      assert_equal first.id, second.reload.parent_id
    end
  end

  test "POST indent on first child returns 422" do
    with_isolated_miolimos_base do
      lonely = WorkNode.create!(topic: @topic, knowledge_item: @ki,
                                  role: "content", position: 1)
      post "/topics/#{@topic.slug}/work_nodes/#{lonely.id}/indent",
           as: :json
      assert_response :unprocessable_content
    end
  end

  test "POST outdent promotes node to grandparent level" do
    with_isolated_miolimos_base do
      parent = WorkNode.create!(topic: @topic, knowledge_item: @ki,
                                  role: "heading", position: 1)
      child  = WorkNode.create!(topic: @topic, parent: parent,
                                  knowledge_item: @ki, role: "content", position: 1)
      post "/topics/#{@topic.slug}/work_nodes/#{child.id}/outdent",
           headers: { "Accept" => "text/vnd.turbo-stream.html" }
      assert_response :success
      assert_nil child.reload.parent_id
    end
  end

  test "POST outdent on root returns 422" do
    with_isolated_miolimos_base do
      root = WorkNode.create!(topic: @topic, knowledge_item: @ki,
                                role: "content", position: 1)
      post "/topics/#{@topic.slug}/work_nodes/#{root.id}/outdent",
           as: :json
      assert_response :unprocessable_content
    end
  end
end
