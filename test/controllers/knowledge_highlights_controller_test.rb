require "test_helper"

# #378 Phase 3 (Hans, 2026-05-26): Tests fuer den ausgelagerten
# KnowledgeHighlightsController. URL bleibt unter
# /knowledge_items/:uuid/wrap_highlight.
class KnowledgeHighlightsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @hans = HumanActor.create!(
      name: "Hans", email: "hans-highlights-#{SecureRandom.hex(3)}@t.local",
      password: "secretsecret"
    )
    grant(@hans, "KnowledgeItem", %w[read create update delete])
    post "/login", params: { email: @hans.email, password: "secretsecret" }
  end

  def create_note(content)
    FileProxy.create(actor: @hans, title: "Test", item_type: :note, content: content)
  end

  test "POST wrap_highlight wraps the requested block" do
    with_isolated_miolimos_base do
      item = create_note("Erster Absatz.\n\nZweiter Absatz.\n")
      post "/knowledge_items/#{item.uuid}/wrap_highlight",
           params: { anchor: "block-2", color: "gelb" },
           as: :json
      assert_response :success
      # Reload: Controller laedt eine eigene Instanz; das lokale `item`
      # ist nach dem Roundtrip stale.
      item.reload
      body = FileProxy.read_body(actor: @hans, knowledge_item: item)
      assert_match(/==gelb\|Zweiter Absatz/, body)
    end
  end

  test "POST wrap_highlight with color=keine unwraps existing highlights" do
    with_isolated_miolimos_base do
      item = create_note("Hervorgehoben.\n")
      BodyHighlightWrapper.call(item: item, actor: @hans,
        anchor: "block-1", color: "gelb")
      pre = FileProxy.read_body(actor: @hans, knowledge_item: item.reload)
      assert_match(/==gelb\|/, pre, "Pre-condition: must be wrapped before unwrap test")

      post "/knowledge_items/#{item.uuid}/wrap_highlight",
           params: { anchor: "block-1", color: "keine" },
           as: :json
      assert_response :success
      item.reload
      body = FileProxy.read_body(actor: @hans, knowledge_item: item)
      assert_no_match(/==gelb\|/, body)
    end
  end

  test "POST wrap_highlight returns 422 on invalid color" do
    with_isolated_miolimos_base do
      item = create_note("Text.\n")
      post "/knowledge_items/#{item.uuid}/wrap_highlight",
           params: { anchor: "block-1", color: "neon" },
           as: :json
      assert_response :unprocessable_content
      json = JSON.parse(response.body)
      assert_match(/Farbe/, json["error"])
    end
  end
end
