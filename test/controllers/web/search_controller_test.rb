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

  # ── #1321 (Hans, 2026-08-07): Ergebnis-Card ───────────────────────────

  test "Dropdown bietet den Einstieg in die Ergebnis-Card an" do
    Task.create!(creator: @hans, title: "Dropdownprobe", status: :open)
    get "/search", params: { q: "dropdownprobe" }
    assert_response :success
    assert_includes response.body, I18n.t("search.show_all")
    # Der Payload reist als blade-link-Wert mit (im href steht er
    # URL-kodiert, deshalb hier das data-Attribut prüfen).
    assert_includes response.body,
      "data-blade-link-id-value=\"#{SearchQuery.encode_payload("dropdownprobe")}\""
    assert_includes response.body, "data-blade-link-kind-value=\"search_list\""
  end

  test "Dropdown ohne Treffer bietet KEINEN Einstieg an" do
    get "/search", params: { q: "voellig-unauffindbar-xyz" }
    assert_response :success
    assert_not_includes response.body, I18n.t("search.show_all")
  end

  test "list_card zeigt Sektionskopf mit Trefferzahl und laedt Zeilen NICHT mit" do
    Task.create!(creator: @hans, title: "Cardprobe eins", status: :open)
    Task.create!(creator: @hans, title: "Cardprobe zwei", status: :open)
    get "/search/list_card", params: { p: SearchQuery.encode_payload("cardprobe") }
    assert_response :success
    assert_includes response.body, I18n.t("search.sections.tasks")
    # Sektionen sind eingeklappt und lazy — die Titel stehen noch nicht drin.
    assert_not_includes response.body, "Cardprobe eins"
    assert_includes response.body, "search/section"
    assert_includes response.body, 'loading="lazy"'
  end

  test "list_card traegt die Stack-Id der Card" do
    payload = SearchQuery.encode_payload("cardprobe")
    get "/search/list_card", params: { p: payload }
    assert_includes response.body, "data-uuid=\"list:search:#{payload}\""
  end

  test "section liefert die Zeilen einer Sektion" do
    Task.create!(creator: @hans, title: "Sektionsprobe", status: :open)
    get "/search/section", params: { p: SearchQuery.encode_payload("sektionsprobe"), section: "tasks" }
    assert_response :success
    assert_includes response.body, "Sektionsprobe"
  end

  test "section bietet weitere anzeigen erst ab mehr Treffern als das Limit" do
    (SearchQuery::PAGE_SIZE + 3).times { |i| Task.create!(creator: @hans, title: "Vieleprobe #{i}", status: :open) }
    payload = SearchQuery.encode_payload("vieleprobe")
    get "/search/section", params: { p: payload, section: "tasks" }
    assert_response :success
    assert_includes response.body, I18n.t("search.load_more", count: 3)

    get "/search/section", params: { p: payload, section: "tasks", limit: 100 }
    assert_response :success
    assert_not_includes response.body, I18n.t("search.load_more", count: 3)
  end

  test "section mit unbekannter Sammlung ist 404" do
    get "/search/section", params: { p: SearchQuery.encode_payload("egal"), section: "gibtsnicht" }
    assert_response :not_found
  end

  test "kaputter payload ist 404 statt 500" do
    get "/search/list_card", params: { p: "!!!kein base64!!!" }
    assert_response :not_found
  end

  # Jede Sammlung einmal wirklich rendern — die Zeilen-Helfer greifen je
  # Sammlung auf andere Felder zu (display_title, display_authors, Datums-
  # formate). Ein Tippfehler dort fiele sonst erst Hans auf.
  test "jede Sammlung rendert ihre Trefferzeile" do
    term = "renderprobe"
    Task.create!(creator: @hans, title: "#{term} Aufgabe", status: :open)
    # #602 S1: Kommunikation hat keinen Ersteller — sichtbar wird sie über
    # ihre Themen-Zuordnung (oder das eigene Postfach).
    comm = Communication.create!(direction: "inbound", subject: "#{term} Mail",
                                 external_id: "rp-#{SecureRandom.hex(4)}", sent_at: Time.current)
    CommunicationTopic.create!(communication: comm,
                               topic: Topic.create!(name: "Postfach", creator: @hans,
                                                    slug: "rp-post-#{SecureRandom.hex(2)}"))
    Document.create!(kind: :brief, subject: "#{term} Brief", creator: @hans,
                     document_date: Date.current)
    Invoice.create!(kind: :rechnung, subject: "#{term} Rechnung", creator: @hans,
                    document_date: Date.current)
    Topic.create!(name: "#{term} Thema", slug: "rp-#{SecureRandom.hex(2)}", creator: @hans)
    Source.create!(slug: "rp-#{SecureRandom.hex(3)}", csl_type: "book",
                   title: "#{term} Quelle", creator: @hans)
    Awaiting.create!(title: "#{term} Wiedervorlage", follow_up_at: Date.current, creator: @hans)
    InboxItem.create!(source_kind: "text", title: "#{term} Schnipsel", creator: @hans)

    payload = SearchQuery.encode_payload(term)
    %w[tasks communications documents invoices topics sources awaitings inbox_items].each do |section|
      get "/search/section", params: { p: payload, section: section }
      assert_response :success, "Sektion #{section} muss rendern"
      assert_includes response.body, term, "Sektion #{section} muss ihren Treffer zeigen"
    end
  end

  # Reload/Lesezeichen: die Card muss auch serverseitig aus dem ?stack=-Param
  # entstehen, nicht nur per JS-Append.
  test "Ergebnis-Card ueberlebt einen Stack-Restore ueber ?stack=" do
    Task.create!(creator: @hans, title: "Restoreprobe", status: :open)
    payload = SearchQuery.encode_payload("restoreprobe")
    get "/dashboard", params: { stack: "list:dashboard,list:search:#{payload}" }
    assert_response :success
    assert_includes response.body, "data-uuid=\"list:search:#{payload}\""
    assert_includes response.body, I18n.t("search.sections.tasks")
  end

  test "Suchbegriff mit Komma ueberlebt den kommaseparierten stack-Param" do
    Task.create!(creator: @hans, title: "Kommaprobe, zweiter Teil", status: :open)
    payload = SearchQuery.encode_payload("kommaprobe, zweiter")
    assert_not_includes payload, ","
    get "/search/section", params: { p: payload, section: "tasks" }
    assert_response :success
    assert_includes response.body, "Kommaprobe, zweiter Teil"
  end
end
