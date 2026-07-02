require "test_helper"

class KnowledgeAnchorsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @hans = HumanActor.create!(
      name: "Hans", email: "hans-ka-#{SecureRandom.hex(3)}@t.local",
      password: "secretsecret"
    )
    grant(@hans, "KnowledgeItem", %w[read create update])
    post "/login", params: { email: @hans.email, password: "secretsecret" }
  end

  test "POST ensure_anchor with block-N returns a stable anchor id" do
    with_isolated_miolimos_base do
      ki = FileProxy.create(actor: @hans, title: "Anch", item_type: :note,
                            content: "First paragraph.\n\nSecond paragraph.")
      post "/knowledge_items/#{ki.uuid}/ensure_anchor", params: { anchor: "block-1" }
      assert_response :ok
      body = JSON.parse(@response.body)
      assert_equal ki.uuid, body["uuid"]
      # #466: vereinheitlichtes Anker-Format — Block-Anker sind jetzt 8-Hex.
      assert_match(/\A[a-f0-9]{8}\z/, body["anchor"])
    end
  end

  test "POST ensure_anchor returns 422 for out-of-range block index" do
    with_isolated_miolimos_base do
      ki = FileProxy.create(actor: @hans, title: "Range", item_type: :note,
                            content: "only one paragraph")
      post "/knowledge_items/#{ki.uuid}/ensure_anchor", params: { anchor: "block-99" }
      assert_response :unprocessable_entity
      body = JSON.parse(@response.body)
      assert body["error"].present?
    end
  end

  test "POST comment_at creates a comment KI and returns its uuid" do
    with_isolated_miolimos_base do
      ki = FileProxy.create(actor: @hans, title: "Source", item_type: :note,
                            content: "Real paragraph one.\n\nRetro paragraph two.")
      assert_difference -> { KnowledgeItem.count }, 1 do
        post "/knowledge_items/#{ki.uuid}/comment_at", params: { anchor: "block-1" }
      end
      assert_response :ok
      body = JSON.parse(@response.body)
      assert body["uuid"].present?
      assert body["anchor"].present?
      created = KnowledgeItem.find(body["uuid"])
      assert_equal "comment", created.item_type
    end
  end

  # #467 (Hans, 2026-06-02): Aufgabe an einem Anker erzeugen — Beschreibung
  # traegt den Wikilink auf den Anker.
  test "POST task_at creates a task linking to the anchor" do
    with_isolated_miolimos_base do
      ki = FileProxy.create(actor: @hans, title: "Quelle-XZ", item_type: :note,
                            content: "Erster Absatz.\n\nZweiter Absatz.")
      assert_difference -> { Task.count }, 1 do
        post "/knowledge_items/#{ki.uuid}/task_at",
             params: { anchor: "block-1", title: "Erster Absatz." }
      end
      assert_response :ok
      task = Task.find(JSON.parse(@response.body)["task_id"])
      assert_equal "Erster Absatz.", task.title
      assert_match %r{\[\[Quelle-XZ\^[a-z0-9]+\]\]}, task.description
    end
  end

  # #512 (Hans, 2026-06-04): research=1 → Recherche-Aufgabe, die aufs
  # Entitäts-Recherche-Verfahren verweist (statt LLM-Job).
  test "POST task_at with research=1 creates a research task referencing the Verfahren" do
    with_isolated_miolimos_base do
      ki = FileProxy.create(actor: @hans, title: "Quelle-RB", item_type: :note,
                            content: "Ein Absatz über Robert Bjork.")
      post "/knowledge_items/#{ki.uuid}/task_at",
           params: { anchor: "block-1", title: "Robert Bjork", hints: "UCLA", research: "1" }
      assert_response :ok
      task = Task.find(JSON.parse(@response.body)["task_id"])
      assert task.title.start_with?("Recherche:")
      assert_includes task.description, "[[Verfahren: Entitäts-Recherche]]"
      assert_match %r{\[\[Quelle-RB\^[a-z0-9]+\]\]}, task.description
      assert_includes task.description, "UCLA"
    end
  end

  # #466 (Hans, 2026-06-02): Aufgabe aus einer Antwort — Titel NICHT mit
  # dem markierten Text vorbelegen (Platzhalter), Wikilink mit Alternate-
  # Display „Thread-Antwort" (Anker-only -> Resolver loest auf Parent auf).
  test "POST task_at aus einer Antwort: Platzhalter-Titel + Thread-Antwort-Link" do
    with_isolated_miolimos_base do
      parent = FileProxy.create(actor: @hans, title: "Eltern-KI",
                                item_type: :note, content: "x")
      reply  = FileProxy.create(actor: @hans, title: "r", item_type: :reply,
                                content: "Antwort-Absatz.\n")
      reply.update!(title: nil, parent_type: "KnowledgeItem",
                    parent_uuid: parent.uuid, published_at: Time.current)
      post "/knowledge_items/#{reply.uuid}/task_at",
           params: { anchor: "block-1", title: "markierter Text" }
      assert_response :ok
      body = JSON.parse(@response.body)
      assert_equal true, body["reply"]
      task = Task.find(body["task_id"])
      assert_equal "Neue Aufgabe", task.title
      # #466: vereinheitlichter 8-Hex-Block-Anker (ensure_anchor) +
      # Thread-Antwort-Alias.
      assert_match %r{\A\[\[\^[a-f0-9]{8}\|Thread-Antwort\]\]\z}, task.description
      # Der Anker muss in KnowledgeItemAnchor indiziert sein (Update-Pfad
      # synct jetzt auch), sonst loest der [[^anker]]-Link nicht auf.
      anchor = task.description[/\^([a-f0-9]{8})\|/, 1]
      assert KnowledgeItemAnchor.exists?(anchor: anchor, knowledge_item_uuid: reply.uuid),
             "Block-Anker #{anchor} wurde nicht in KnowledgeItemAnchor indiziert"
    end
  end

  test "POST start_research_at enqueues a research job" do
    with_isolated_miolimos_base do
      ki = FileProxy.create(actor: @hans, title: "Res", item_type: :note,
                            content: "Important paragraph here.")
      assert_enqueued_with(job: ParagraphResearchJob) do
        post "/knowledge_items/#{ki.uuid}/start_research_at",
             params: { anchor: "block-1", hints: "kontextfrage" }
      end
      assert_response :ok
    end
  end

  test "GET backlinks lists KIs that reference this anchor" do
    with_isolated_miolimos_base do
      target = FileProxy.create(actor: @hans, title: "Target", item_type: :note,
                                content: "Target content")
      source = FileProxy.create(actor: @hans, title: "Source", item_type: :note,
                                content: "ref note")
      KnowledgeItemReference.create!(
        source_uuid: source.uuid, target_uuid: target.uuid,
        target_title: target.title, anchor_type: :block, anchor_text: "abc123"
      )

      get "/knowledge_items/#{target.uuid}/backlinks", params: { anchor: "abc123" }
      assert_response :ok
      body = JSON.parse(@response.body)
      uuids = body["items"].map { |i| i["uuid"] }
      assert_includes uuids, source.uuid
    end
  end

  test "without KnowledgeItem.update capability, ensure_anchor is forbidden" do
    with_isolated_miolimos_base do
      ki = FileProxy.create(actor: @hans, title: "Lock", item_type: :note, content: "x")

      read_only = HumanActor.create!(
        name: "RO", email: "ro2-#{SecureRandom.hex(3)}@t.local",
        password: "secretsecret"
      )
      grant(read_only, "KnowledgeItem", %w[read])
      post "/login", params: { email: read_only.email, password: "secretsecret" }

      post "/knowledge_items/#{ki.uuid}/ensure_anchor", params: { anchor: "block-1" }
      assert_response :forbidden
    end
  end
end
