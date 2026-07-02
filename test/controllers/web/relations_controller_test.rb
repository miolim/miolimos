require "test_helper"

class RelationsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @hans = HumanActor.create!(
      name: "Hans", email: "hans-rel-#{SecureRandom.hex(3)}@t.local",
      password: "secretsecret", role: :admin
    )
    grant(@hans, "KnowledgeItem", %w[read create update])
    post "/login", params: { email: @hans.email, password: "secretsecret" }

    @source = KnowledgeItem.create!(uuid: SecureRandom.uuid, title: "Quelle",
                                    item_type: :note, file_path: "x/quelle.md",
                                    content_hash: "h", body: "")
    @target = KnowledgeItem.create!(uuid: SecureRandom.uuid, title: "Ziel",
                                    item_type: :note, file_path: "x/ziel.md",
                                    content_hash: "h", body: "")
    @rel = Relation.create!(source_uuid: @source.uuid, source_type: "KnowledgeItem",
                            target_uuid: @target.uuid, target_type: "KnowledgeItem",
                            anchor_id: "abc123", direction: "source_to_target")
  end

  test "GET show liefert Relation als JSON" do
    get "/knowledge_items/#{@source.uuid}/relations/#{@rel.anchor_id}",
        headers: { "Accept" => "application/json" }
    assert_response :ok
    data = JSON.parse(@response.body)
    assert_equal "abc123", data["anchor_id"]
    assert_equal @source.uuid, data["source_uuid"]
    assert_equal @target.uuid, data["target_uuid"]
    assert_equal "Ziel", data["target_title"]
    assert_equal "source_to_target", data["direction"]
  end

  test "GET show 404 bei unbekanntem anchor" do
    get "/knowledge_items/#{@source.uuid}/relations/zzzzzz",
        headers: { "Accept" => "application/json" }
    assert_response :not_found
  end

  test "PATCH update setzt Label/Description/Direction und Provenance" do
    patch "/knowledge_items/#{@source.uuid}/relations/#{@rel.anchor_id}",
          params: { relation: { label: "loest aus", description: "warum",
                                direction: "bidirectional" } }.to_json,
          headers: { "Content-Type" => "application/json",
                     "Accept" => "application/json" }
    assert_response :ok
    @rel.reload
    assert_equal "loest aus", @rel.label
    assert_equal "warum", @rel.description
    assert_equal "bidirectional", @rel.direction
    assert_equal @hans.id, @rel.recognized_by_id
    refute_nil @rel.recognized_at
  end

  test "PATCH update mit ungueltiger direction → 422" do
    patch "/knowledge_items/#{@source.uuid}/relations/#{@rel.anchor_id}",
          params: { relation: { direction: "invalid" } }.to_json,
          headers: { "Content-Type" => "application/json",
                     "Accept" => "application/json" }
    assert_response :unprocessable_content
    data = JSON.parse(@response.body)
    assert data["errors"].any?
  end

  test "POST typify fuegt anchor in Wikilink ein und liefert Anchor zurueck" do
    with_isolated_miolimos_base do
      target = FileProxy.create(actor: @hans, title: "ZielKI", item_type: :note, content: "")
      src    = FileProxy.create(actor: @hans, title: "QuelleKI", item_type: :note,
                                 content: "Sieh [[ZielKI]] da.")

      post "/knowledge_items/#{src.uuid}/relations/typify",
           params: { occurrence: 1 }.to_json,
           headers: { "Content-Type" => "application/json",
                      "Accept" => "application/json" }
      assert_response :ok
      data = JSON.parse(@response.body)
      assert_match(/\A[0-9a-z]{6}\z/, data["anchor_id"])
      assert_equal target.uuid, data["target_uuid"]
      src.reload
      assert_includes src.body, "^#{data['anchor_id']}"
    end
  end

  test "POST typify mit ungueltiger occurrence → 422" do
    with_isolated_miolimos_base do
      src = FileProxy.create(actor: @hans, title: "Solo", item_type: :note,
                              content: "Kein Wikilink hier.")
      post "/knowledge_items/#{src.uuid}/relations/typify",
           params: { occurrence: 1 }.to_json,
           headers: { "Content-Type" => "application/json",
                      "Accept" => "application/json" }
      assert_response :unprocessable_content
    end
  end

  test "PATCH update bewahrt erstmalige Provenance" do
    other = HumanActor.create!(name: "Erika",
                               email: "erika-rel-#{SecureRandom.hex(3)}@t.local",
                               password: "secretsecret")
    @rel.update!(recognized_by: other, recognized_at: 1.day.ago)
    original_at = @rel.recognized_at

    patch "/knowledge_items/#{@source.uuid}/relations/#{@rel.anchor_id}",
          params: { relation: { label: "neu" } }.to_json,
          headers: { "Content-Type" => "application/json",
                     "Accept" => "application/json" }
    assert_response :ok
    @rel.reload
    assert_equal other.id, @rel.recognized_by_id, "recognized_by bleibt"
    assert_in_delta original_at.to_f, @rel.recognized_at.to_f, 1.0,
                    "recognized_at bleibt"
  end
end
