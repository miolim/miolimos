require "test_helper"

# #378 Phase 7 (Hans, 2026-05-26): Tests fuer KiTemplatesController —
# Picker-Suggest fuer KI-Quick-Create (#301).
class KiTemplatesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @hans = HumanActor.create!(
      name: "Hans", email: "hans-kit-#{SecureRandom.hex(3)}@t.local",
      password: "secretsecret"
    )
    grant(@hans, "KnowledgeItem", %w[read create update delete])
    post "/login", params: { email: @hans.email, password: "secretsecret" }
  end

  test "GET /ki_templates/suggest returns matching templates as JSON" do
    t = KiTemplate.create!(name: "Meeting-Notiz", item_type: "note",
                            title: "Meeting", body: "...")
    KiTemplate.create!(name: "Andere", item_type: "note")
    get "/ki_templates/suggest", params: { q: "meeting" }
    assert_response :success
    json = JSON.parse(response.body)
    names = json.map { |h| h["name"] }
    assert_includes names, "Meeting-Notiz"
    assert_includes json.first.keys, "item_type"
    assert_includes json.first.keys, "body"
  end

  test "GET /ki_templates/suggest empty q returns all (limit 8, ordered by name)" do
    10.times { |i| KiTemplate.create!(name: "T#{i.to_s.rjust(2, '0')}", item_type: "note") }
    get "/ki_templates/suggest"
    assert_response :success
    json = JSON.parse(response.body)
    assert_equal 8, json.size
    names = json.map { |h| h["name"] }
    assert_equal names.sort, names
  end
end
