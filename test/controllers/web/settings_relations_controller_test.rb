require "test_helper"

class Settings::RelationsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @hans = HumanActor.create!(
      name: "Hans", email: "hans-srel-#{SecureRandom.hex(3)}@t.local",
      password: "secretsecret"
    )
    grant(@hans, "KnowledgeItem", %w[read])
    grant(@hans, "Actor", %w[read])
    post "/login", params: { email: @hans.email, password: "secretsecret" }

    @source = KnowledgeItem.create!(uuid: SecureRandom.uuid, title: "Quelle",
                                    item_type: :note, file_path: "x/q.md",
                                    content_hash: "h", body: "")
    @target = KnowledgeItem.create!(uuid: SecureRandom.uuid, title: "Ziel",
                                    item_type: :note, file_path: "x/z.md",
                                    content_hash: "h", body: "")
  end

  test "GET /settings/relations aggregiert Labels nach Anzahl" do
    Relation.create!(source_uuid: @source.uuid, source_type: "KnowledgeItem",
                     target_uuid: @target.uuid, target_type: "KnowledgeItem",
                     anchor_id: "aaa111", label: "loest aus")
    Relation.create!(source_uuid: @source.uuid, source_type: "KnowledgeItem",
                     target_uuid: @target.uuid, target_type: "KnowledgeItem",
                     anchor_id: "bbb222", label: "loest aus")
    Relation.create!(source_uuid: @source.uuid, source_type: "KnowledgeItem",
                     target_uuid: @target.uuid, target_type: "KnowledgeItem",
                     anchor_id: "ccc333", label: "widerspricht")

    get "/settings/relations"
    follow_redirect!   # #613
    assert_response :success
    assert_includes @response.body, "loest aus"
    assert_includes @response.body, "widerspricht"
    # #613: Beziehungstypen jetzt als Blade-Label statt Tab
    assert_includes @response.body, "Beziehungstypen"
  end

  test "Empty-State wenn keine Relations" do
    get "/settings/relations"
    follow_redirect!   # #613
    assert_response :success
    assert_includes @response.body, "Noch keine benannten Beziehungen"
  end

  test "POST /settings/relations legt einen RelationType an" do
    grant(@hans, "KnowledgeItem", %w[read create update])
    assert_difference -> { RelationType.count }, 1 do
      post "/settings/relations", params: { relation_type: { name: "blockiert", inverse_name: "wird blockiert von" } }
    end
    assert_redirected_to settings_relations_path
  end

  test "PATCH /settings/relations/:id aktualisiert einen RelationType" do
    grant(@hans, "KnowledgeItem", %w[read create update])
    rt = RelationType.create!(name: "alt", inverse_name: "rueckwaerts")
    patch "/settings/relations/#{rt.id}",
          params: { relation_type: { name: "neu", inverse_name: "neu rueckwaerts" } }
    assert_redirected_to settings_relations_path
    rt.reload
    assert_equal "neu", rt.name
    assert_equal "neu rueckwaerts", rt.inverse_name
  end

  test "DELETE /settings/relations/:id loescht einen RelationType" do
    grant(@hans, "KnowledgeItem", %w[read create update delete])
    rt = RelationType.create!(name: "weg")
    assert_difference -> { RelationType.count }, -1 do
      delete "/settings/relations/#{rt.id}"
    end
  end

  test "Orphaned + label-loese Relations stehen im Header-Counter" do
    Relation.create!(source_uuid: @source.uuid, source_type: "KnowledgeItem",
                     target_uuid: @target.uuid, target_type: "KnowledgeItem",
                     anchor_id: "ddd444", label: nil)
    Relation.create!(source_uuid: @source.uuid, source_type: "KnowledgeItem",
                     target_uuid: @target.uuid, target_type: "KnowledgeItem",
                     anchor_id: "eee555", label: "x", orphaned_at: Time.current)

    get "/settings/relations"
    follow_redirect!   # #613
    assert_response :success
    assert_includes @response.body, "ohne Label"
    assert_includes @response.body, "verwaist"
  end
end
