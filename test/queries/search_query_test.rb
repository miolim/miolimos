require "test_helper"

# #1321 (Hans, 2026-08-07): SearchQuery ist DIE Such-Definition — Dropdown und
# Ergebnis-Card lesen beide hier. Die Tests decken vor allem die Sammlungen ab,
# die vor #1321 gar nicht durchsucht wurden.
class SearchQueryTest < ActiveSupport::TestCase
  setup do
    @hans = create_human(email: "sq-#{SecureRandom.hex(3)}@t.local")
  end

  def q(text) = SearchQuery.new(text, actor: @hans)

  # ── Payload (Stack-Id) ────────────────────────────────────────────────

  test "payload roundtrip haelt Umlaute, Komma und Leerzeichen aus" do
    ["Grundstück, Meier", "a b c", "Übergabe"].each do |text|
      payload = SearchQuery.encode_payload(text)
      assert_not_includes payload, ","
      assert_equal text, SearchQuery.decode_payload(payload)
      assert_equal Encoding::UTF_8, SearchQuery.decode_payload(payload).encoding
    end
  end

  test "kaputter payload wirft BadPayload statt zu crashen" do
    assert_raises(SearchQuery::BadPayload) { SearchQuery.decode_payload("!!!nicht base64!!!") }
  end

  # ── Kurze Eingaben ────────────────────────────────────────────────────

  test "unter MIN_LENGTH wird gar nicht gesucht" do
    Task.create!(creator: @hans, title: "Aaa", status: :open)
    assert q("a").blank?
    assert_equal 0, q("a").total
    assert_empty q("a").records(:tasks, limit: 20)
  end

  # ── Zaehlung und Nachladen ────────────────────────────────────────────

  test "count zaehlt alle Treffer, records liefert nur das Limit" do
    5.times { |i| Task.create!(creator: @hans, title: "Zaehlprobe #{i}", status: :open) }
    search = q("zaehlprobe")
    assert_equal 5, search.count(:tasks)
    assert_equal 2, search.records(:tasks, limit: 2).size
    assert_equal 5, search.records(:tasks, limit: 20).size
  end

  test "hit_sections nennt nur Sammlungen mit Treffern" do
    Task.create!(creator: @hans, title: "Nurhiertreffer", status: :open)
    assert_equal [:tasks], q("nurhiertreffer").hit_sections
  end

  # ── Sammlungen, die vor #1321 fehlten ─────────────────────────────────

  test "findet Kommunikation im Nachrichtentext, nicht nur im Betreff" do
    Communication.create!(direction: "inbound", subject: "Ohne Bezug",
                          body: "Im Text steht Dachrinnensanierung.",
                          external_id: "sq-#{SecureRandom.hex(4)}")
    assert_equal 1, q("dachrinnensanierung").count(:communications)
  end

  test "findet Dokumente ueber den Betreff" do
    Document.create!(kind: :brief, subject: "Kündigung Stellplatz", creator: @hans)
    assert_equal 1, q("stellplatz").count(:documents)
  end

  test "findet Themen ueber Name und Beschreibung" do
    Topic.create!(name: "Heizungstausch", slug: "heizungstausch-#{SecureRandom.hex(2)}",
                  creator: @hans, description: "Angebote einholen")
    assert_equal 1, q("heizungstausch").count(:topics)
    assert_equal 1, q("angebote einholen").count(:topics)
  end

  test "findet Quellen ueber Titel und Abstract" do
    Source.create!(slug: "src-#{SecureRandom.hex(3)}", csl_type: "book",
                   title: "Handbuch Mietrecht", abstract: "Zur Betriebskostenabrechnung",
                   creator: @hans)
    assert_equal 1, q("mietrecht").count(:sources)
    assert_equal 1, q("betriebskostenabrechnung").count(:sources)
  end

  test "findet Wiedervorlagen ueber Titel" do
    Awaiting.create!(title: "Rückruf Hausverwaltung", follow_up_at: Date.current, creator: @hans)
    assert_equal 1, q("hausverwaltung").count(:awaitings)
  end

  test "findet Inbox-Eintraege ueber den Rohtext" do
    InboxItem.create!(source_kind: "text", title: "Schnipsel",
                      raw_content: "Termin beim Schornsteinfeger", creator: @hans)
    assert_equal 1, q("schornsteinfeger").count(:inbox_items)
  end

  # ── Bestehendes Verhalten bleibt ──────────────────────────────────────

  test "#<nr> stellt die Aufgabe mit dieser Nummer vorne ein" do
    other  = Task.create!(creator: @hans, title: "Irgendwas", status: :open)
    direct = Task.create!(creator: @hans, title: "Ohne Texttreffer", status: :open)
    _ = other
    records = q("##{direct.id}").records(:tasks, limit: 20)
    assert_equal direct.id, records.first.id
  end

  test "unbekannte Sektion fliegt auf die Nase statt still leer zu liefern" do
    assert_raises(ArgumentError) { q("egal").count(:gibtsnicht) }
  end

  # ── Snippets ──────────────────────────────────────────────────────────

  test "excerpt_html markiert die Fundstelle und escaped den Rest" do
    html = q("dach").excerpt_html("Am <b>Dach</b> ist was")
    assert_includes html, "<mark>Dach</mark>"
    assert_includes html, "&lt;b&gt;"
    assert_not_includes html, "<b>"
  end

  test "excerpt_html liefert nil, wenn der Begriff im Feld nicht vorkommt" do
    assert_nil q("dach").excerpt_html("Nichts davon hier")
  end
end
