require "test_helper"

class Api::V1::KnowledgeItemsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @creator = create_human
    grant(@creator, "KnowledgeItem", %w[read create update delete])
    @agent = AgentActor.create!(name: "ki-#{SecureRandom.hex(3)}", description: "t")
    grant(@agent, "KnowledgeItem", %w[read create update delete])
    @headers = { "Authorization" => "Bearer #{@agent.api_token}" }
  end

  def build_item(**overrides)
    defaults = {
      uuid:         SecureRandom.uuid,
      title:        "Sample",
      item_type:    :note,

      file_path:    "knowledge/notes/#{SecureRandom.hex(4)}.md",
      content_hash: SecureRandom.hex(32),
      file_created_at: Time.current,
      file_updated_at: Time.current,
      indexed_at:      Time.current
    }
    KnowledgeItem.create!(**defaults.merge(overrides))
  end

  test "index returns UUID-keyed items" do
    build_item(title: "K1")
    build_item(title: "K2")
    get "/api/v1/knowledge_items", headers: @headers
    assert_response :success
    body = JSON.parse(response.body)
    assert body["data"].first.key?("uuid")
  end

  test "index filters by item_type and topic_slug" do
    topic = Topic.create!(name: "t", slug: "km-topic-#{SecureRandom.hex(3)}", creator: @creator)
    note = build_item(title: "n", item_type: :note)
    chat = build_item(title: "c", item_type: :abstract)
    KnowledgeItemTopic.create!(knowledge_item: chat, topic: topic)

    get "/api/v1/knowledge_items", params: { item_type: "abstract", topic_slug: topic.slug },
        headers: @headers
    uuids = JSON.parse(response.body)["data"].map { |k| k["uuid"] }
    assert_equal [chat.uuid], uuids
  end

  test "show by uuid" do
    k = build_item(title: "unique-item")
    get "/api/v1/knowledge_items/#{k.uuid}", headers: @headers
    assert_response :success
    assert_equal k.uuid, JSON.parse(response.body)["data"]["uuid"]
  end

  test "show 404 for unknown uuid" do
    get "/api/v1/knowledge_items/#{SecureRandom.uuid}", headers: @headers
    assert_response :not_found
  end

  test "POST creates a knowledge item through FileProxy" do
    with_isolated_miolimos_base do
      post "/api/v1/knowledge_items",
           params: { title: "API-Notiz", item_type: "note",
                     content: "body", topics: ["api-slug"] },
           headers: @headers
      assert_response :created

      body = JSON.parse(response.body)["data"]
      item = KnowledgeItem.find(body["uuid"])
      assert_equal "API-Notiz", item.title
      assert item.topics.pluck(:slug).include?("api-slug")
    end
  end

  test "PATCH updates title, content and tags through FileProxy" do
    with_isolated_miolimos_base do
      post "/api/v1/knowledge_items",
           params: { title: "Vorher", item_type: "note", content: "alt" },
           headers: @headers
      uuid = JSON.parse(response.body)["data"]["uuid"]

      patch "/api/v1/knowledge_items/#{uuid}",
            params: { title: "Nachher", content: "neuer body", tags: ["x"] },
            headers: @headers
      assert_response :success

      item = KnowledgeItem.find(uuid)
      assert_equal "Nachher", item.title
      assert_equal "neuer body", item.body.to_s.strip
      assert_includes item.tags.to_a, "x"
    end
  end

  test "PATCH partial update leaves untouched fields intact" do
    with_isolated_miolimos_base do
      post "/api/v1/knowledge_items",
           params: { title: "Titel", item_type: "note", content: "korpus", tags: ["keep"] },
           headers: @headers
      uuid = JSON.parse(response.body)["data"]["uuid"]

      patch "/api/v1/knowledge_items/#{uuid}",
            params: { content: "nur body neu" },
            headers: @headers
      assert_response :success

      item = KnowledgeItem.find(uuid)
      assert_equal "Titel", item.title
      assert_equal "nur body neu", item.body.to_s.strip
      assert_includes item.tags.to_a, "keep"
    end
  end

  test "PATCH enforces update capability, not read" do
    reader = AgentActor.create!(name: "ro-#{SecureRandom.hex(3)}", description: "t")
    grant(reader, "KnowledgeItem", %w[read])
    with_isolated_miolimos_base do
      post "/api/v1/knowledge_items",
           params: { title: "T", item_type: "note", content: "b" },
           headers: @headers
      uuid = JSON.parse(response.body)["data"]["uuid"]

      patch "/api/v1/knowledge_items/#{uuid}",
            params: { title: "X" },
            headers: { "Authorization" => "Bearer #{reader.api_token}" }
      assert_response :forbidden
    end
  end

  test "DELETE soft-deletes a knowledge item" do
    with_isolated_miolimos_base do
      post "/api/v1/knowledge_items",
           params: { title: "Wegwerf", item_type: "note", content: "x" },
           headers: @headers
      uuid = JSON.parse(response.body)["data"]["uuid"]

      delete "/api/v1/knowledge_items/#{uuid}", headers: @headers
      assert_response :success
      assert KnowledgeItem.unscoped.find_by(uuid: uuid).deleted_at.present?
    end
  end

  test "GET /:uuid/history lists git commits of the KI" do
    with_isolated_miolimos_base do
      post "/api/v1/knowledge_items",
           params: { title: "Versioniert", item_type: "note", content: "v1" },
           headers: @headers
      uuid = JSON.parse(response.body)["data"]["uuid"]
      patch "/api/v1/knowledge_items/#{uuid}",
            params: { content: "v2" }, headers: @headers

      get "/api/v1/knowledge_items/#{uuid}/history", headers: @headers
      assert_response :success
      commits = JSON.parse(response.body)["data"]
      assert commits.is_a?(Array)
      assert commits.size >= 2, "expected create + update commits, got #{commits.size}"
      assert commits.first.key?("sha")
    end
  end

  test "POST /:uuid/restore_version writes an old version back as a new commit" do
    with_isolated_miolimos_base do
      post "/api/v1/knowledge_items",
           params: { title: "Restorebar", item_type: "note", content: "ORIGINAL" },
           headers: @headers
      uuid = JSON.parse(response.body)["data"]["uuid"]
      patch "/api/v1/knowledge_items/#{uuid}",
            params: { content: "GEAENDERT" }, headers: @headers

      get "/api/v1/knowledge_items/#{uuid}/history", headers: @headers
      commits = JSON.parse(response.body)["data"]
      old_sha = commits.last["sha"] # ältester = create mit ORIGINAL

      post "/api/v1/knowledge_items/#{uuid}/restore_version",
           params: { sha: old_sha }, headers: @headers
      assert_response :success
      assert_equal "ORIGINAL", KnowledgeItem.find(uuid).body.to_s.strip
    end
  end

  test "PATCH sets and clears supersession" do
    with_isolated_miolimos_base do
      post "/api/v1/knowledge_items", params: { title: "Alt", item_type: "note", content: "a" }, headers: @headers
      old = JSON.parse(response.body)["data"]["uuid"]
      post "/api/v1/knowledge_items", params: { title: "Neu", item_type: "note", content: "b" }, headers: @headers
      neu = JSON.parse(response.body)["data"]["uuid"]

      patch "/api/v1/knowledge_items/#{old}", params: { superseded_by_uuid: neu }, headers: @headers
      assert_response :success
      data = JSON.parse(response.body)["data"]
      assert_equal neu, data["superseded_by_uuid"]
      assert data["superseded_at"].present?
      assert KnowledgeItem.find(old).superseded?

      patch "/api/v1/knowledge_items/#{old}", params: { superseded_by_uuid: "" }, headers: @headers
      assert_response :success
      assert_not KnowledgeItem.find(old).superseded?
    end
  end

  test "PATCH self-supersession is rejected (422)" do
    with_isolated_miolimos_base do
      post "/api/v1/knowledge_items", params: { title: "Selbst", item_type: "note", content: "a" }, headers: @headers
      uuid = JSON.parse(response.body)["data"]["uuid"]
      patch "/api/v1/knowledge_items/#{uuid}", params: { superseded_by_uuid: uuid }, headers: @headers
      assert_response :unprocessable_entity
    end
  end

  test "PATCH supersession with unknown successor 404s" do
    with_isolated_miolimos_base do
      post "/api/v1/knowledge_items", params: { title: "X", item_type: "note", content: "a" }, headers: @headers
      uuid = JSON.parse(response.body)["data"]["uuid"]
      patch "/api/v1/knowledge_items/#{uuid}", params: { superseded_by_uuid: SecureRandom.uuid }, headers: @headers
      assert_response :not_found
    end
  end

  test "GET /:uuid/content streams file body" do
    with_isolated_miolimos_base do
      item = FileProxy.create(
        actor: @creator, title: "Readable", item_type: :note, content: "golden text"
      )
      grant(@agent, "KnowledgeItem", %w[read])
      get "/api/v1/knowledge_items/#{item.uuid}/content", headers: @headers
      assert_response :success
      body = JSON.parse(response.body)["data"]
      assert_equal item.uuid, body["uuid"]
      assert_includes body["content"], "golden text"
    end
  end

  test "GET /:uuid/content liefert auch nach File-Delete den Content aus DB (Plan B #241)" do
    with_isolated_miolimos_base do |base|
      item = FileProxy.create(
        actor: @creator, title: "Gone", item_type: :note, content: "x"
      )
      File.delete(base.join(item.file_path))

      get "/api/v1/knowledge_items/#{item.uuid}/content", headers: @headers
      assert_response :success
      body = JSON.parse(response.body)["data"]
      assert_includes body["content"], "# Gone", "Title aus DB rekonstruiert"
      assert_includes body["content"], "x",      "Body aus DB-Spalte"
    end
  end

  test "content endpoint enforces read capability, not update" do
    with_isolated_miolimos_base do
      item = FileProxy.create(
        actor: @creator, title: "x", item_type: :note, content: "x"
      )

      ro = AgentActor.create!(name: "ro-#{SecureRandom.hex(3)}", description: "t")
      grant(ro, "KnowledgeItem", %w[read])

      get "/api/v1/knowledge_items/#{item.uuid}/content",
          headers: { "Authorization" => "Bearer #{ro.api_token}" }
      assert_response :success
    end
  end

  # ─── append ─────────────────────────────────────────────────────────────

  test "POST /append creates new abstract when no target matches" do
    with_isolated_miolimos_base do
      content = <<~MD
        ---
        title: Brainstorming Session
        chat_title: Original Chat Title
        source_url: https://claude.ai/chat/abc-123
        topics: [foo, bar]
        tags: [chat, exploration]
        ---

        # Brainstorming Session

        Erste Notizen aus dem Chat.
      MD

      assert_difference -> { KnowledgeItem.count }, 1 do
        post "/api/v1/knowledge_items/append",
             params: { content: content }, headers: @headers
      end
      assert_response :created

      body = JSON.parse(response.body)
      assert_equal "created", body["meta"]["outcome"]

      item = KnowledgeItem.find(body["data"]["uuid"])
      assert_equal "Brainstorming Session", item.title
      assert_equal "abstract", item.item_type
      # source_url + chat_title sind keine KI-Felder mehr — sie liegen
      # über bib_source. Die Append-API legt eine personal_communication-
      # Source aus dem chat_title an (wenn keine Source mit der URL
      # existiert) und verlinkt das KI.
      assert_not_nil item.bib_source
      assert_equal "https://claude.ai/chat/abc-123", item.bib_source.url
    end
  end

  test "POST /append appends to existing item when append_to UUID matches" do
    with_isolated_miolimos_base do
      target = FileProxy.create(actor: @creator, title: "Working Notes",
                                item_type: :abstract, content: "alte Notizen")

      content = <<~MD
        ---
        append_to: #{target.uuid}
        ---

        Nächster Stand vom Chat.
      MD

      assert_no_difference -> { KnowledgeItem.count } do
        post "/api/v1/knowledge_items/append",
             params: { content: content }, headers: @headers
      end
      assert_response :success

      body = JSON.parse(response.body)
      assert_equal "appended", body["meta"]["outcome"]
      assert_equal target.uuid, body["data"]["uuid"]

      raw_body = FileProxy.read(actor: @creator, knowledge_item: target.reload)
      assert_match(/Nächster Stand vom Chat/, raw_body)
      assert_match(/alte Notizen/, raw_body)  # alter Body bleibt erhalten
      assert_match(/^## Session \d{4}-\d{2}-\d{2}/, raw_body)
    end
  end

  test "POST /append matches by source_url (über bib_source.url) vor title-Fallback" do
    with_isolated_miolimos_base do
      src    = Source.create!(slug: "claude-xyz", csl_type: "personal_communication",
                              title: "Original Chat", url: "https://claude.ai/chat/xyz",
                              creator: @creator)
      target = FileProxy.create(actor: @creator, title: "Original",
                                item_type: :abstract,
                                content: "vorher")
      target.update!(bib_source_id: src.id)

      content = <<~MD
        ---
        title: Other Title
        source_url: https://claude.ai/chat/xyz
        ---

        Update.
      MD

      assert_no_difference -> { KnowledgeItem.count } do
        post "/api/v1/knowledge_items/append",
             params: { content: content }, headers: @headers
      end
      body = JSON.parse(response.body)
      assert_equal "appended", body["meta"]["outcome"]
      assert_equal target.uuid, body["data"]["uuid"]
    end
  end

  test "POST /append injects override params into light header" do
    with_isolated_miolimos_base do
      content = "Reine Body-Notizen ohne Frontmatter."

      assert_difference -> { KnowledgeItem.count }, 1 do
        post "/api/v1/knowledge_items/append",
             params: { content: content,
                       title: "Override Title",
                       source_url: "https://example.com/chat",
                       topics: ["alpha", "beta"] },
             headers: @headers
      end
      body = JSON.parse(response.body)
      item = KnowledgeItem.find(body["data"]["uuid"])
      assert_equal "Override Title", item.title
      assert_equal "https://example.com/chat", item.bib_source&.url
      assert_equal %w[alpha beta].sort, item.topics.pluck(:slug).sort
    end
  end

  test "POST /append returns 422 when neither frontmatter nor params supply a title" do
    with_isolated_miolimos_base do
      assert_no_difference -> { KnowledgeItem.count } do
        post "/api/v1/knowledge_items/append",
             params: { content: "Nur ein Body, kein Header." },
             headers: @headers
      end
      assert_response :unprocessable_entity
      assert_equal "title required for new item", JSON.parse(response.body)["error"]
    end
  end

  test "POST /append matches existing item by title (case-insensitive) when no UUID/URL" do
    with_isolated_miolimos_base do
      target = FileProxy.create(actor: @creator, title: "My Chat",
                                item_type: :abstract, content: "stand 1")

      assert_no_difference -> { KnowledgeItem.count } do
        post "/api/v1/knowledge_items/append",
             params: { content: "Nachtrag.", title: "my chat" },
             headers: @headers
      end
      body = JSON.parse(response.body)
      assert_equal "appended", body["meta"]["outcome"]
      assert_equal target.uuid, body["data"]["uuid"]
    end
  end

  # #708 (Hans): Personen-Serialisierung muss Adresse/Kontakt/IDs enthalten.
  test "Personen-KI liefert postal_addresses, contact_points, identifiers" do
    person = build_item(title: "Adressperson", item_type: :person)
    person.postal_addresses.create!(kind: "liegenschaft", line1: "Hauptstr. 1",
                                    postal_code: "12345", city: "Berlin")
    person.contact_points.create!(kind: "phone", value: "+49 30 123")
    person.identifiers.create!(label: "IBAN", value: "DE123")

    get "/api/v1/knowledge_items/#{person.uuid}", headers: @headers
    assert_response :success
    data = JSON.parse(response.body)["data"]
    assert_equal 1, data["postal_addresses"].size
    assert_equal "Hauptstr. 1", data["postal_addresses"].first["line1"]
    assert_equal "Berlin",      data["postal_addresses"].first["city"]
    assert_equal "+49 30 123",  data["contact_points"].first["value"]
    assert_equal "DE123",       data["identifiers"].first["value"]

    # Wie der Agent einem Wikilink folgt: index mit title-Filter.
    get "/api/v1/knowledge_items?title=Adressperson", headers: @headers
    assert_response :success
    item = JSON.parse(response.body)["data"].first
    assert_equal "Hauptstr. 1", item["postal_addresses"].first["line1"]
  end

  test "Nicht-Personen-KI hat leere Kontakt-Arrays" do
    note = build_item(title: "Nur Notiz", item_type: :note)
    get "/api/v1/knowledge_items/#{note.uuid}", headers: @headers
    data = JSON.parse(response.body)["data"]
    assert_equal [], data["postal_addresses"]
    assert_equal [], data["contact_points"]
  end

  # #708 (Hans): Agent kann Kontaktdaten pflegen (Replace je Feld).
  test "update pflegt postal_addresses/contact_points/identifiers" do
    person = build_item(title: "Pflegeperson", item_type: :person)
    patch "/api/v1/knowledge_items/#{person.uuid}",
      params: {
        postal_addresses: [{ kind: "liegenschaft", line1: "Weg 2", postal_code: "10115", city: "Berlin" }],
        contact_points:   [{ kind: "email", value: "a@b.de" }, { kind: "phone", value: "+49 1" }],
        identifiers:      [{ label: "IBAN", value: "DE99" }]
      }, headers: @headers, as: :json
    assert_response :success
    person.reload
    assert_equal "Weg 2", person.postal_addresses.first.line1
    assert_equal 2,       person.contact_points.count
    assert_equal "DE99",  person.identifiers.first.value

    # Replace: leeres Array leert nur dieses Feld; ungesendete bleiben.
    patch "/api/v1/knowledge_items/#{person.uuid}",
      params: { contact_points: [] }, headers: @headers, as: :json
    assert_response :success
    person.reload
    assert_equal 0, person.contact_points.count
    assert_equal 1, person.postal_addresses.count
  end

  test "update mit ungültigem contact_point-kind antwortet 422" do
    person = build_item(title: "Bad-CP", item_type: :person)
    patch "/api/v1/knowledge_items/#{person.uuid}",
      params: { contact_points: [{ kind: "telepathy", value: "x" }] },
      headers: @headers, as: :json
    assert_response :unprocessable_entity
    assert_equal 0, person.reload.contact_points.count   # atomar, nichts angelegt
  end
end
