require "test_helper"

# #1631 (aus immoOS #1608 übernommen). Hans dort: „Vorher bitte eine Nachfrage
# einbauen, die die Konsequenzen aufzeigt und dann erst auf Bestätigung
# zusammenführt."
class KnowledgeItemsMergePreview1631Test < ActionDispatch::IntegrationTest
  STREAM = { "Accept" => "text/vnd.turbo-stream.html" }.freeze

  setup do
    @hans = create_human(password: "secretsecret")
    grant(@hans, "KnowledgeItem", %w[read create update delete])
    post "/login", params: { email: @hans.email, password: "secretsecret" }
  end

  test "die Auswahl zeigt erst die Nachfrage mit den Folgen und führt nicht zusammen" do
    with_isolated_miolimos_base do
      source = FileProxy.create(actor: @hans, title: "Muster", item_type: :person, content: "",
                                topics: [], contacts: [], tags: [])
      target = FileProxy.create(actor: @hans, title: "Erika Muster", item_type: :person, content: "",
                                topics: [], contacts: [], tags: [])
      source.contact_points.create!(kind: "email", value: "muster@example.org")

      post "/knowledge_items/#{source.uuid}/merge_preview", params: { target_uuid: target.uuid }, headers: STREAM

      assert_response :success
      assert_includes response.body, %(target="knowledge_merge_chip_#{source.uuid}")
      assert_includes response.body, CGI.escapeHTML(I18n.t("knowledge.detail.merge_confirm_title",
                                                           source: "Muster", target: "Erika Muster"))
      assert_includes response.body, "/knowledge_items/#{source.uuid}/merge", "der Bestätigen-Knopf ruft den Merge"

      assert_not KnowledgeItem.with_discarded.find(source.uuid).discarded?
      assert_equal ["muster@example.org"], source.reload.contact_points.pluck(:value)
    end
  end

  test "ein unbekanntes Ziel wird abgewiesen" do
    with_isolated_miolimos_base do
      source = FileProxy.create(actor: @hans, title: "Wer", item_type: :person, content: "",
                                topics: [], contacts: [], tags: [])

      post "/knowledge_items/#{source.uuid}/merge_preview", params: { target_uuid: SecureRandom.uuid }, headers: STREAM

      assert_response :unprocessable_entity
      assert_not KnowledgeItem.find(source.uuid).discarded?
    end
  end

  test "der Merge-Picker zeigt auf die Nachfrage, nicht auf den Merge" do
    html = File.read(Rails.root.join("app/views/knowledge_items/_detail_section.html.erb"))

    assert_includes html, "add_url:       merge_preview_knowledge_item_path(item.uuid)"
    assert_not_includes html, "add_url:       merge_knowledge_item_path(item.uuid)"
  end
end
