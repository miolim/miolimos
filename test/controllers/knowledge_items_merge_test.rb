require "test_helper"

# #1075: Merge-Action im Web-Controller — Quelle geht im Ziel auf,
# Response räumt die Quell-Card aus Stack und Liste.
class KnowledgeItemsMergeTest < ActionDispatch::IntegrationTest
  setup do
    @hans = HumanActor.create!(
      name: "Hans", email: "hans-merge-#{SecureRandom.hex(3)}@t.local",
      password: "secretsecret"
    )
    grant(@hans, "KnowledgeItem", %w[read create update delete])
    post "/login", params: { email: @hans.email, password: "secretsecret" }
  end

  test "POST merge fuehrt zusammen und entfernt die Quell-Card" do
    with_isolated_miolimos_base do
      source = FileProxy.create(actor: @hans, title: "Stocker", item_type: :person, content: "")
      target = FileProxy.create(actor: @hans, title: "Angela Stocker", item_type: :person, content: "")
      source.contact_points.create!(kind: "email", value: "stocker@faro-immo.de")

      post "/knowledge_items/#{source.uuid}/merge",
           params: { target_uuid: target.uuid },
           headers: { "Accept" => "text/vnd.turbo-stream.html" }
      assert_response :success
      assert_includes response.body, "stack_card_#{source.uuid}"

      assert KnowledgeItem.with_discarded.find(source.uuid).discarded?
      assert_equal ["stocker@faro-immo.de"], target.reload.contact_points.pluck(:value)
      assert_includes target.aliases.to_a, "Stocker"
    end
  end

  test "POST merge mit unbekanntem Ziel liefert 422" do
    with_isolated_miolimos_base do
      source = FileProxy.create(actor: @hans, title: "Wer", item_type: :person, content: "")
      post "/knowledge_items/#{source.uuid}/merge",
           params: { target_uuid: SecureRandom.uuid },
           headers: { "Accept" => "text/vnd.turbo-stream.html" }
      assert_response :unprocessable_entity
      assert_not KnowledgeItem.find(source.uuid).discarded?
    end
  end
end
