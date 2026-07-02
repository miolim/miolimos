require "test_helper"

# #378 Phase 7 (Hans, 2026-05-26): Tests fuer KnowledgeItemTagsController
# (Tags-Array auf KI; analog TaskTagsController).
class KnowledgeItemTagsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @hans = HumanActor.create!(
      name: "Hans", email: "hans-kit-#{SecureRandom.hex(3)}@t.local",
      password: "secretsecret"
    )
    grant(@hans, "KnowledgeItem", %w[read create update delete])
    post "/login", params: { email: @hans.email, password: "secretsecret" }
  end

  test "POST appends a new tag (lowercase, dedup)" do
    with_isolated_miolimos_base do
      item = FileProxy.create(actor: @hans, title: "T", item_type: :note, content: "x",
                                tags: ["alpha"])
      post "/knowledge_items/#{item.uuid}/tags",
           params: { create_with: "BETA" },
           headers: { "Accept" => "text/vnd.turbo-stream.html" }
      assert_response :success
      assert_equal %w[alpha beta], item.reload.tags
    end
  end

  test "POST is idempotent on existing tag" do
    with_isolated_miolimos_base do
      item = FileProxy.create(actor: @hans, title: "T", item_type: :note, content: "x",
                                tags: ["alpha"])
      post "/knowledge_items/#{item.uuid}/tags",
           params: { create_with: "alpha" },
           headers: { "Accept" => "text/vnd.turbo-stream.html" }
      assert_response :success
      assert_equal ["alpha"], item.reload.tags
    end
  end

  test "POST with empty tag returns 422" do
    with_isolated_miolimos_base do
      item = FileProxy.create(actor: @hans, title: "T", item_type: :note, content: "x")
      post "/knowledge_items/#{item.uuid}/tags", params: { create_with: " " },
           as: :json
      assert_response :unprocessable_entity
    end
  end

  test "DELETE removes the tag (case-insensitive)" do
    with_isolated_miolimos_base do
      item = FileProxy.create(actor: @hans, title: "T", item_type: :note, content: "x",
                                tags: %w[alpha beta gamma])
      delete "/knowledge_items/#{item.uuid}/tags/BETA",
             headers: { "Accept" => "text/vnd.turbo-stream.html" }
      assert_response :success
      assert_equal %w[alpha gamma], item.reload.tags
    end
  end

  test "DELETE on non-existent tag is a no-op" do
    with_isolated_miolimos_base do
      item = FileProxy.create(actor: @hans, title: "T", item_type: :note, content: "x",
                                tags: ["alpha"])
      delete "/knowledge_items/#{item.uuid}/tags/zeta",
             headers: { "Accept" => "text/vnd.turbo-stream.html" }
      assert_response :success
      assert_equal ["alpha"], item.reload.tags
    end
  end
end
