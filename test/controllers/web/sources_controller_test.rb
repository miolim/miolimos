require "test_helper"

class SourcesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @hans = HumanActor.create!(
      name: "Hans", email: "hans-src-#{SecureRandom.hex(3)}@t.local",
      password: "secretsecret"
    )
    grant(@hans, "Source",        %w[read create update delete])
    grant(@hans, "KnowledgeItem", %w[read create])
    post "/login", params: { email: @hans.email, password: "secretsecret" }
  end

  def make_source(attrs = {})
    Source.create!({
      slug: "smith-2020-#{SecureRandom.hex(3)}",
      title: "Smith 2020",
      csl_type: "book",
      creator: @hans
    }.merge(attrs))
  end

  test "GET index renders list" do
    s = make_source(title: "Hidden Constraints")
    get "/sources"
    assert_response :ok
    assert_includes @response.body, s.title
  end

  # #631 v3: /sources ist eine Stack-Seite; Suche läuft client-seitig im
  # Blade — Server-Filter (q/csl_type) sind mit der Vollseite entfallen.
  test "GET index rendert das Quellen-Listen-Blade (#631 v3)" do
    s = make_source(title: "Blade-Quelle")
    get "/sources"
    assert_response :ok
    assert_includes @response.body, %q(data-uuid="list:sources")
    assert_includes @response.body, s.title
  end

  test "GET show als Vollseite leitet auf den Stack (#631 v3)" do
    s = make_source(title: "Solo Show")
    get "/sources/#{s.slug}"
    assert_response :redirect
    assert_includes @response.redirect_url, "src%3A#{s.slug}"
    follow_redirect!
    assert_response :ok
    assert_includes @response.body, s.title
  end

  # #581: Drei-Stufen-Toggle (zu → belegte Felder → alle) an den Details;
  # leere Felder tragen data-empty fürs Ausblenden in der Mittelstufe.
  # #582: gefüllte URL bekommt ein Link-Icon zum Öffnen.
  test "Details-Section: tri-disclosure + data-empty + URL-Link-Icon" do
    s = make_source(title: "Toggle-Quelle", url: "https://example.org/paper",
                    publisher: "Acme Press")
    get "/sources/#{s.slug}"
    follow_redirect!   # #631 v3: Stack-Seite
    assert_response :ok
    assert_includes @response.body, 'data-controller="tri-disclosure"'
    assert_includes @response.body, "tri-disclosure#cycle"
    assert_includes @response.body, 'data-empty="false"'  # publisher/url belegt
    assert_includes @response.body, 'data-empty="true"'   # z.B. Band/Heft leer
    assert_match %r{<a[^>]+target="_blank"[^>]*>}, @response.body
    assert_includes @response.body, 'title="URL öffnen"'
    assert_includes @response.body, 'href="https://example.org/paper"'
  end

  # #584: Voll-Edit in die Details verschmolzen — Titel/Slug/Creators/
  # Identifier sind inline editierbar, der Pencil zur Edit-Page ist weg.
  test "Details enthalten Titel/Slug/Creators/Identifier-Editor, kein Pencil" do
    s = make_source(title: "Merge-Quelle")
    get "/sources/#{s.slug}"
    follow_redirect!   # #631 v3: Stack-Seite
    assert_response :ok
    assert_includes @response.body, "Autoren / Creators"
    assert_includes @response.body, "creators[][knowledge_item_uuid]"
    assert_includes @response.body, "identifiers[][value]"
    assert_includes @response.body, "Slug (Cite-Key)"
    refute_includes @response.body, "Volle Edit-Page"
  end

  # #584-Folge: Autoren-Sub-Section zuoberst — Kompakt-Zeile je Rolle,
  # Namen ohne UUIDs; Server löst Namen auf (bestehend oder neuer Stub).
  test "PATCH creators mit Namen löst Person auf, Kompakt-Zeile rendert Rolle" do
    s = make_source(title: "Creator-Quelle")
    patch "/sources/#{s.slug}",
          params: { source: { title: s.title }, in_stack: "1",
                    creators: [{ knowledge_item_uuid: "Fikes, Richard E.", role: "author" }] },
          headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_response :success
    s.reload
    assert_equal 1, s.source_creators.count
    ki = s.source_creators.first.knowledge_item
    assert_equal "Fikes, Richard E.", ki.title
    assert_includes @response.body, "Autoren:"
    assert_includes @response.body, "Fikes, Richard E."
    refute_includes @response.body, ki.uuid  # keine UUIDs in der Anzeige
  end

  # #649: Die Autoren-Sub-Section submittet NUR creators[] — ohne
  # source-Param darf das kein 400 („Content missing") geben.
  test "PATCH nur mit creators (ohne source-Param) legt Namens-Stub an" do
    s = make_source(title: "Interview-Quelle")
    patch "/sources/#{s.slug}",
          params: { in_stack: "1",
                    creators: [{ knowledge_item_uuid: "" },
                               { knowledge_item_uuid: "Jaron Lanier", role: "author" }] },
          headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_response :success
    s.reload
    assert_equal 1, s.source_creators.count
    assert_equal "Jaron Lanier", s.source_creators.first.knowledge_item.title
  end

  # #584: Slug-Inline-Edit ersetzt das Frame unter der ALTEN DOM-ID.
  test "PATCH slug in_stack ersetzt das alte source_detail-Frame" do
    s = make_source(title: "Slug-Quelle")
    old_slug = s.slug
    patch "/sources/#{old_slug}", params: { source: { slug: "neuer-slug-#{SecureRandom.hex(2)}" }, in_stack: "1" },
          headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_response :success
    assert_match %r{<turbo-stream action="replace" target="source_detail_#{old_slug}"}, @response.body
  end

  test "GET new renders form" do
    get "/sources/new"
    assert_response :ok
    assert_includes @response.body, "csl_type"
  end

  test "POST create with valid params persists source" do
    assert_difference -> { Source.count }, 1 do
      post "/sources", params: {
        source: {
          slug: "popper-1959-logik",
          title: "Logik der Forschung",
          csl_type: "book",
          issued_string: "1959"
        }
      }
    end
    assert_redirected_to "/sources?stack=list%3Asources%2Csrc%3Apopper-1959-logik"   # #631 v3
    s = Source.find_by(slug: "popper-1959-logik")
    assert_equal Date.new(1959, 1, 1), s.issued_date
  end

  test "POST create with invalid slug re-renders form" do
    assert_no_difference -> { Source.count } do
      post "/sources", params: {
        source: { slug: "BAD SLUG!", title: "x", csl_type: "book" }
      }
    end
    assert_response :unprocessable_entity
  end

  test "POST create syncs identifiers" do
    post "/sources", params: {
      source: { slug: "doi-test-#{SecureRandom.hex(3)}",
                title: "DOI Test", csl_type: "article-journal" },
      identifiers: [{ scheme: "DOI", value: "10.1000/abcd" }]
    }
    s = Source.last
    assert_equal 1, s.source_identifiers.count
    assert_equal "DOI", s.source_identifiers.first.scheme
  end

  test "PATCH update changes title and replaces identifiers" do
    s = make_source(title: "Old Title")
    s.source_identifiers.create!(scheme: "ISBN", value: "9780000000001")

    patch "/sources/#{s.slug}", params: {
      source: { slug: s.slug, title: "New Title", csl_type: s.csl_type },
      identifiers: [{ scheme: "DOI", value: "10.1000/new" }]
    }
    assert_redirected_to "/sources?stack=list%3Asources%2Csrc%3A#{s.slug}"   # #631 v3
    assert_equal "New Title", s.reload.title
    assert_equal ["DOI"], s.source_identifiers.pluck(:scheme)
  end

  test "DELETE destroys source" do
    s = make_source
    assert_difference -> { Source.count }, -1 do
      delete "/sources/#{s.slug}"
    end
    assert_redirected_to "/sources"
  end

  test "GET suggest returns matching sources as JSON" do
    s1 = make_source(title: "Apples and Bananas")
    s2 = make_source(title: "Zenith Theory")

    get "/sources/suggest", params: { q: "apple" }
    assert_response :ok
    body = JSON.parse(response.body)
    slugs = body["items"].map { |i| i["slug"] }
    assert_includes slugs, s1.slug
    refute_includes slugs, s2.slug
  end

  test "without Source.delete capability, DELETE is forbidden" do
    no_delete = HumanActor.create!(
      name: "Eve", email: "eve-#{SecureRandom.hex(3)}@t.local",
      password: "secretsecret"
    )
    grant(no_delete, "Source", %w[read create update])
    post "/login", params: { email: no_delete.email, password: "secretsecret" }

    s = make_source
    delete "/sources/#{s.slug}"
    assert_response :forbidden
    assert Source.exists?(s.id)
  end
end
