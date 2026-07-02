require "test_helper"

class Api::V1::KnowledgeRepliesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @creator = create_human
    grant(@creator, "KnowledgeItem", %w[read create update delete])
    @agent = AgentActor.create!(name: "kr-#{SecureRandom.hex(3)}", description: "t")
    grant(@agent, "KnowledgeItem", %w[read create update])
    @headers = { "Authorization" => "Bearer #{@agent.api_token}" }
  end

  test "POST creates a reply-KI threaded to the parent KI" do
    with_isolated_miolimos_base do
      post "/api/v1/knowledge_items",
           params: { title: "Parent", item_type: "note", content: "x", topics: ["disk-topic"] },
           headers: @headers
      parent_uuid = JSON.parse(response.body)["data"]["uuid"]

      assert_difference -> { KnowledgeItem.where(item_type: "reply").count }, 1 do
        post "/api/v1/knowledge_items/#{parent_uuid}/replies",
             params: { body: "Mein Diskussionsbeitrag" },
             headers: @headers
      end
      assert_response :created

      data = JSON.parse(response.body)["data"]
      reply = KnowledgeItem.find(data["id"])
      assert_equal "KnowledgeItem", reply.parent_type
      assert_equal parent_uuid, reply.parent_uuid
      assert_equal "Mein Diskussionsbeitrag", reply.body.to_s.strip
      assert reply.published_at.present?, "reply should be published immediately"
      # erbt Topics des Parents
      assert_includes reply.topics.pluck(:slug), "disk-topic"
    end
  end

  test "POST reply requires body" do
    with_isolated_miolimos_base do
      post "/api/v1/knowledge_items",
           params: { title: "P2", item_type: "note", content: "x" },
           headers: @headers
      parent_uuid = JSON.parse(response.body)["data"]["uuid"]

      post "/api/v1/knowledge_items/#{parent_uuid}/replies",
           params: {}, headers: @headers
      assert_response :bad_request
    end
  end
end
