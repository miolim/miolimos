require "test_helper"

# #378 Phase 6 (Hans, 2026-05-26): Tests fuer SearchController —
# Postgres-FTS-Suche ueber Tasks/KIs/Communications.
class SearchControllerTest < ActionDispatch::IntegrationTest
  setup do
    @hans = HumanActor.create!(
      name: "Hans", email: "hans-search-#{SecureRandom.hex(3)}@t.local",
      password: "secretsecret"
    )
    grant(@hans, "KnowledgeItem", %w[read create update delete])
    grant(@hans, "Task",          %w[read create update delete])
    grant(@hans, "Communication", %w[read create update delete])
    post "/login", params: { email: @hans.email, password: "secretsecret" }
  end

  test "GET /search with empty query renders without results" do
    get "/search", params: { q: "" }
    assert_response :success
  end

  test "GET /search with 1-char query treats as empty (no FTS)" do
    get "/search", params: { q: "a" }
    assert_response :success
  end

  test "GET /search finds tasks by title" do
    Task.create!(creator: @hans, title: "Migration Datenbank",
                  description: "Wichtig", status: :open)
    get "/search", params: { q: "migration" }
    assert_response :success
    assert_includes response.body, "Migration Datenbank"
  end

  # #481 (Hans, 2026-06-03): „#<nr>" findet die Aufgabe direkt per Nummer.
  test "GET /search mit #<nr> findet die Aufgabe ueber ihre Nummer" do
    t = Task.create!(creator: @hans, title: "Eindeutiger-Titel-XYZ-ohne-Treffer",
                     description: "rein", status: :open)
    get "/search", params: { q: "##{t.id}" }
    assert_response :success
    assert_includes response.body, "Eindeutiger-Titel-XYZ-ohne-Treffer"
  end

  test "GET /search mit #<nr> einer unbekannten Nummer bricht nicht" do
    get "/search", params: { q: "#99999999" }
    assert_response :success
  end

  test "GET /search finds knowledge items by body content" do
    with_isolated_miolimos_base do
      FileProxy.create(actor: @hans, title: "Notiz", item_type: :note,
                        content: "Spezieller Suchbegriff Quantenphysik im Body.")
      get "/search", params: { q: "quantenphysik" }
      assert_response :success
      assert_includes response.body, "Notiz"
    end
  end

  test "GET /search finds persons via contact-point email" do
    with_isolated_miolimos_base do
      person = FileProxy.create(actor: @hans, title: "Anna Bauer",
                                  item_type: :person, content: "")
      ContactPoint.create!(knowledge_item_uuid: person.uuid,
                            kind: "email", value: "anna.bauer@example.org")
      get "/search", params: { q: "bauer@example" }
      assert_response :success
      assert_includes response.body, "Anna Bauer"
    end
  end

end
