require "test_helper"

# #1677 (aus immoOS #1656 übernommen; Hans dort): „Könnte man die Personenliste
# auch nach Nachname, Vorname anzeigen und sortieren lassen?" — Umschalter neben
# der Bekanntheit, damit beide Reihenfolgen erreichbar bleiben.
class PersonenlisteNamen1656Test < ActionDispatch::IntegrationTest
  setup do
    @hans = HumanActor.create!(name: "Hans", email: "pl-#{SecureRandom.hex(3)}@t.local",
                               password: "secretsecret")
    %w[KnowledgeItem].each { |rt| grant(@hans, rt, %w[read create update delete]) }
    post "/login", params: { email: @hans.email, password: "secretsecret" }

    @anton  = person("Anton Zimmermann", first: "Anton", last: "Zimmermann")
    @berta  = person("Berta Albers",     first: "Berta", last: "Albers")
    # Ohne erfasste Namensfelder — hier muss der Titel führen.
    @ohne   = person("Zacharias Ohnefeld")
    @org    = KnowledgeItem.create!(uuid: SecureRandom.uuid, title: "Meier GmbH",
                                    item_type: :organization, creator_id: @hans.id,
                                    file_path: "kb/#{SecureRandom.hex(4)}.md",
                                    content_hash: SecureRandom.hex(8))
    # #1656 R2 (Hans): „die drei WEGs stehen ganz oben". Im Bestand tragen
    # sieben Organisationen einen Nachnamen — das letzte Wort ihres Titels,
    # bei den WEGs eine Hausnummer. Sortiert werden darf danach nicht.
    @weg    = KnowledgeItem.create!(uuid: SecureRandom.uuid, title: "WEG Am Speicher 11",
                                    item_type: :organization, last_name: "11",
                                    creator_id: @hans.id,
                                    file_path: "kb/#{SecureRandom.hex(4)}.md",
                                    content_hash: SecureRandom.hex(8))
  end

  def person(title, first: nil, last: nil)
    KnowledgeItem.create!(uuid: SecureRandom.uuid, title: title, item_type: :person,
                          first_name: first, last_name: last, creator_id: @hans.id,
                          file_path: "kb/#{SecureRandom.hex(4)}.md",
                          content_hash: SecureRandom.hex(8))
  end

  # Reihenfolge der Namen, wie sie in der gerenderten Liste steht.
  def reihenfolge(response_body, namen)
    namen.sort_by { |n| response_body.index(n) || Float::INFINITY }
  end

  test "ohne Umschalter bleibt es beim Titel und dessen Sortierung" do
    get "/persons/list_card"
    assert_response :success
    assert_includes @response.body, "Anton Zimmermann"
    assert_equal ["Anton Zimmermann", "Berta Albers", "Meier GmbH"],
                 reihenfolge(@response.body, ["Anton Zimmermann", "Berta Albers", "Meier GmbH"])
  end

  test "#1656: mit Nachname zuerst wird umgestellt — Anzeige UND Sortierung" do
    get "/persons/list_card", params: { namen: "nachname" }
    assert_response :success

    assert_includes @response.body, "Albers, Berta"
    assert_includes @response.body, "Zimmermann, Anton"
    assert_not_includes @response.body, "Anton Zimmermann"
    assert_equal ["Albers, Berta", "Meier GmbH", "Zimmermann, Anton"],
                 reihenfolge(@response.body, ["Albers, Berta", "Meier GmbH", "Zimmermann, Anton"]),
                 "sortiert nach dem, was angezeigt wird"
  end

  test "#1656 R2: eine Organisation sortiert nach ihrem Titel, nicht nach last_name" do
    get "/persons/list_card", params: { namen: "nachname" }
    assert_response :success
    # Nach Titel einsortiert (W…), nicht wegen der „11" ganz oben.
    assert_equal ["Albers, Berta", "Meier GmbH", "WEG Am Speicher 11", "Zimmermann, Anton"],
                 reihenfolge(@response.body,
                             ["Albers, Berta", "Meier GmbH", "WEG Am Speicher 11", "Zimmermann, Anton"])
  end

  # Ohne erfassten Nachnamen wäre jede Umstellung geraten — dann führt der Titel.
  test "#1656: Personen ohne Nachnamen behalten ihren Titel" do
    get "/persons/list_card", params: { namen: "nachname" }
    assert_includes @response.body, "Zacharias Ohnefeld"
  end

  test "#1656: der Umschalter nimmt die anderen Filter mit" do
    get "/persons/list_card", params: { namen: "nachname", known: "personal" }
    assert_response :success
    # Der Rück-Umschalter behält known=personal …
    assert_match(/persons\/list_card\?[^"]*known=personal/, @response.body)
    # … und der Bekanntheits-Umschalter behält namen=nachname.
    assert_match(/persons\/list_card\?[^"]*namen=nachname/, @response.body)
  end

  # #1677: Beim Übertragen gefunden. Die Liste lädt ihre Einträge in der Ansicht
  # selbst — und tat das ohne Sichtbarkeitsfilter (#602): Ein Mitglied sah ALLE
  # Kontakte, auch die eines Themas, in dem es nicht Mitglied ist. (`@hans` hier
  # ist ohne Rolle angelegt, also selbst ein Mitglied, und sieht seine eigenen.)
  test "die Liste zeigt nur Kontakte, die der Nutzer sehen darf" do
    chefin = create_human(name: "Chefin")
    fremd  = KnowledgeItem.create!(uuid: SecureRandom.uuid, title: "Geheimer Investor",
                                   item_type: :person, creator_id: chefin.id,
                                   file_path: "kb/#{SecureRandom.hex(4)}.md",
                                   content_hash: SecureRandom.hex(8))
    get "/persons/list_card"
    assert_response :success
    assert_includes response.body, "Anton Zimmermann"
    refute_includes response.body, fremd.title
  end
end