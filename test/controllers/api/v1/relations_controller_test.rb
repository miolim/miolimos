require "test_helper"

class Api::V1::RelationsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @agent = AgentActor.create!(name: "rel-#{SecureRandom.hex(3)}", description: "t")
    grant(@agent, "KnowledgeItem", %w[read create update])
    @headers = { "Authorization" => "Bearer #{@agent.api_token}" }

    @source = KnowledgeItem.create!(uuid: SecureRandom.uuid, title: "Quelle",
                                    item_type: :note, file_path: "x/q-#{SecureRandom.hex(3)}.md",
                                    content_hash: "h", body: "")
    @target = KnowledgeItem.create!(uuid: SecureRandom.uuid, title: "Ziel",
                                    item_type: :note, file_path: "x/z-#{SecureRandom.hex(3)}.md",
                                    content_hash: "h", body: "")
    @rel = Relation.create!(source_uuid: @source.uuid, source_type: "KnowledgeItem",
                            target_uuid: @target.uuid, target_type: "KnowledgeItem",
                            anchor_id: "abc123", direction: "source_to_target")
  end

  test "GET index lists relations of the source KI" do
    get "/api/v1/knowledge_items/#{@source.uuid}/relations", headers: @headers
    assert_response :ok
    data = JSON.parse(response.body)["data"]
    assert_equal 1, data.size
    assert_equal "abc123", data.first["anchor_id"]
    assert_equal "Ziel",   data.first["target_title"]
  end

  test "GET show returns one relation with ebene from RelationType" do
    RelationType.create!(name: "loest aus", ebene: "inhaltlich")
    @rel.update!(label: "loest aus")
    get "/api/v1/knowledge_items/#{@source.uuid}/relations/abc123", headers: @headers
    assert_response :ok
    data = JSON.parse(response.body)["data"]
    assert_equal "loest aus", data["label"]
    assert_equal "inhaltlich", data["ebene"]
  end

  test "PATCH update sets label/description/direction + stamps provenance" do
    patch "/api/v1/knowledge_items/#{@source.uuid}/relations/abc123",
          params: { relation: { label: "widerspricht", description: "warum",
                                direction: "bidirectional", recognized_role: "agent" } },
          headers: @headers
    assert_response :ok
    @rel.reload
    assert_equal "widerspricht", @rel.label
    assert_equal "warum", @rel.description
    assert_equal "bidirectional", @rel.direction
    assert_equal "agent", @rel.recognized_role
    assert_equal @agent.id, @rel.recognized_by_id
    refute_nil @rel.recognized_at
  end

  test "PATCH update mit ungueltiger direction → 422" do
    patch "/api/v1/knowledge_items/#{@source.uuid}/relations/abc123",
          params: { relation: { direction: "quatsch" } },
          headers: @headers
    assert_response :unprocessable_entity
  end

  test "GET show 404 bei unbekanntem anchor" do
    get "/api/v1/knowledge_items/#{@source.uuid}/relations/zzzzzz", headers: @headers
    assert_response :not_found
  end

  test "ohne Token → 401" do
    get "/api/v1/knowledge_items/#{@source.uuid}/relations"
    assert_response :unauthorized
  end
end
