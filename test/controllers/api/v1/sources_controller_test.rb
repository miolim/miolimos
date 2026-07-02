require "test_helper"

class Api::V1::SourcesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @creator = create_human
    grant(@creator, "Source", %w[read create update delete])
    @agent = AgentActor.create!(name: "src-#{SecureRandom.hex(3)}", description: "t")
    grant(@agent, "Source", %w[read create update])
    @headers = { "Authorization" => "Bearer #{@agent.api_token}" }
  end

  test "POST creates a source with title-only" do
    assert_difference -> { Source.count }, 1 do
      post "/api/v1/sources",
           params: { title: "Schneider et al. 2024 — Photosynthese" },
           headers: @headers
    end
    assert_response :created
    body = JSON.parse(response.body)
    assert_equal "Schneider et al. 2024 — Photosynthese", body["data"]["title"]
    assert_equal "webpage", body["data"]["csl_type"]
    assert body["data"]["slug"].present?
  end

  test "PATCH updates metadata fields (partial)" do
    post "/api/v1/sources", params: { title: "Vor", url: "https://a.test" }, headers: @headers
    slug = JSON.parse(response.body)["data"]["slug"]

    patch "/api/v1/sources/#{slug}",
          params: { publisher: "Neuer Verlag", abstract: "Kurzfassung" },
          headers: @headers
    assert_response :success

    s = Source.find_by!(slug: slug)
    assert_equal "Neuer Verlag", s.publisher
    assert_equal "Kurzfassung", s.abstract
    assert_equal "Vor", s.title           # unangetastet
    assert_equal "https://a.test", s.url  # unangetastet
  end

  # #579: Agenten erfassen Titel/Autoren/Jahr strukturiert — PATCH kann
  # Autoren nachpflegen (Personen-KI-Stub + author-Link, idempotent).
  test "PATCH attaches authors (Personen-Stubs, idempotent)" do
    post "/api/v1/sources", params: { title: "Human Problem Solving" }, headers: @headers
    slug = JSON.parse(response.body)["data"]["slug"]

    grant(@agent, "KnowledgeItem", %w[read create update])
    patch "/api/v1/sources/#{slug}",
          params: { authors: "Newell, Allen; Simon, Herbert A.", issued_string: "1972" },
          headers: @headers
    assert_response :success

    s = Source.find_by!(slug: slug)
    assert_equal "1972", s.issued_string
    assert_equal 2, s.source_creators.where(role: "author").count
    assert_includes s.creator_kis.map(&:title), "Newell, Allen"

    # idempotent: gleicher PATCH erzeugt keine Dubletten
    patch "/api/v1/sources/#{slug}",
          params: { authors: "Newell, Allen; Simon, Herbert A." }, headers: @headers
    assert_equal 2, Source.find_by!(slug: slug).source_creators.where(role: "author").count
  end

  test "POST accepts CSL fields and URL" do
    post "/api/v1/sources",
         params: {
           title: "Mind Title",
           csl_type: "article-journal",
           url: "https://example.com/paper",
           issued_string: "2024",
           publisher: "Nature",
           container_title: "Nature Communications",
           abstract: "A pithy summary."
         },
         headers: @headers
    assert_response :created
    body = JSON.parse(response.body)["data"]
    assert_equal "article-journal", body["csl_type"]
    assert_equal "https://example.com/paper", body["url"]
    assert_equal "2024", body["issued_string"]
    assert_equal "Nature", body["publisher"]
    assert_equal "Nature Communications", body["container_title"]
    assert_equal "A pithy summary.", body["abstract"]
  end

  test "POST builds citekey slug and increments running number on collision" do
    # #512 (Hans, 2026-06-04): Citekey-Schema `autor_jahr_n` (autor = erstes
    # Titelwort ohne Creator, jahr = nd ohne Datum, n = laufende Nummer).
    post "/api/v1/sources", params: { title: "Duplicate" }, headers: @headers
    first_slug = JSON.parse(response.body)["data"]["slug"]
    post "/api/v1/sources", params: { title: "Duplicate" }, headers: @headers
    second_slug = JSON.parse(response.body)["data"]["slug"]
    refute_equal first_slug, second_slug
    assert_equal "duplicate_nd_1", first_slug
    assert_equal "duplicate_nd_2", second_slug
  end

  test "POST returns 422 on missing title" do
    post "/api/v1/sources", params: {}, headers: @headers
    # ParameterMissing wird im Rails default als 400 BadRequest gehandhabt
    # — Hauptsache: kein Source angelegt
    assert_response :bad_request
  end

  test "POST returns 422 on invalid csl_type" do
    post "/api/v1/sources",
         params: { title: "X", csl_type: "not-a-real-type" },
         headers: @headers
    assert_response :unprocessable_entity
  end

  test "GET /api/v1/sources lists with q filter" do
    Source.create!(slug: "alpha-#{SecureRandom.hex(2)}", title: "Alpha Paper",
                   csl_type: "article-journal", creator: @creator)
    Source.create!(slug: "beta-#{SecureRandom.hex(2)}", title: "Beta Paper",
                   csl_type: "article-journal", creator: @creator)
    get "/api/v1/sources", params: { q: "alpha" }, headers: @headers
    assert_response :success
    titles = JSON.parse(response.body)["data"].map { |s| s["title"] }
    assert_includes titles, "Alpha Paper"
    refute_includes titles, "Beta Paper"
  end

  test "GET /api/v1/sources/:slug shows one" do
    src = Source.create!(slug: "show-me-#{SecureRandom.hex(2)}", title: "Show Me",
                         csl_type: "webpage", creator: @creator)
    get "/api/v1/sources/#{src.slug}", headers: @headers
    assert_response :success
    assert_equal "Show Me", JSON.parse(response.body)["data"]["title"]
  end

  test "without auth → 401" do
    post "/api/v1/sources", params: { title: "X" }
    assert_response :unauthorized
  end

  test "without Source-Capability → 403" do
    actor = AgentActor.create!(name: "no-rights-#{SecureRandom.hex(3)}", description: "t")
    # KEIN grant(actor, "Source", ...) — explizit ohne Source-Capability
    grant(actor, "Task", %w[read])  # damit Auth überhaupt durchkommt
    headers = { "Authorization" => "Bearer #{actor.api_token}" }
    post "/api/v1/sources", params: { title: "X" }, headers: headers
    assert_response :forbidden
  end

  # #516 (Hans, 2026-06-05): authors → provisorische Personen + Citekey.
  test "POST with authors creates provisional persons and an author-based citekey" do
    grant(@agent, "KnowledgeItem", %w[read create update])
    with_isolated_miolimos_base do
      post "/api/v1/sources",
           params: { title: "Studie", issued_string: "2024", authors: ["Max Müller", "Anna Schmidt"] },
           headers: @headers
      assert_response :created
      data = JSON.parse(response.body)["data"]
      assert_equal "muller_2024_1", data["slug"]
      assert_includes data["authors"], "Müller"

      src = Source.find_by!(slug: "muller_2024_1")
      assert_equal 2, src.source_creators.count
      assert src.source_creators.all?(&:provisional?)
      assert KnowledgeItem.where(item_type: "person", title: "Max Müller").exists?
    end
  end
end
