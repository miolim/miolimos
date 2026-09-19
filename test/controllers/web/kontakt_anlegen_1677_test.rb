require "test_helper"

# #1677 (aus immoOS #1661 übernommen; Hans dort): „Können alle Stellen, wo
# Personen ausgewählt werden, so gebaut werden, dass dort auch neue Personen
# angelegt werden?" — Findet die Suche nichts, bietet das Auswahlfeld
# „als Person anlegen" / „als Organisation anlegen"; die Vorbelegung richtet
# sich nach dem Feld (Aussteller und Kunde: Organisation, Empfänger: Person).
class KontaktAnlegen1677Test < ActionDispatch::IntegrationTest
  setup do
    @hans = create_human(password: "secretsecret")
    CapabilityDefaults.grant_full!(@hans)
    post "/login", params: { email: @hans.email, password: "secretsecret" }
  end

  def stream = { "Accept" => "text/vnd.turbo-stream.html" }

  test "Dokument: ein unbekannter Aussteller entsteht als Organisation — ohne Namensteile" do
    with_isolated_miolimos_base do
      brief = Document.create!(kind: :brief, creator: @hans)
      assert_difference -> { KnowledgeItem.where(item_type: :organization).count }, 1 do
        post link_document_path(brief, field: "issuer"), params: { create_with: "Stadtwerke Eutin GmbH" }, headers: stream
      end
      org = KnowledgeItem.find_by(title: "Stadtwerke Eutin GmbH")
      assert_equal org.uuid, brief.reload.issuer_uuid
      assert_nil org.last_name, "eine Organisation hat keinen Nachnamen (#1656: stünde sonst unter „GmbH“)"
    end
  end

  test "Dokument: ein unbekannter Empfänger entsteht als Person mit Vor- und Nachname" do
    with_isolated_miolimos_base do
      brief = Document.create!(kind: :brief, creator: @hans)
      post link_document_path(brief, field: "recipient"), params: { create_with: "Anna Maria Bergmann" }, headers: stream
      person = KnowledgeItem.find_by(title: "Anna Maria Bergmann")
      assert_equal "person", person.item_type
      assert_equal ["Anna Maria", "Bergmann"], [person.first_name, person.last_name]
      assert_equal person.uuid, brief.reload.recipient_uuid
    end
  end

  test "die Wahl im Auswahlfeld (create_type) schlaegt die Vorbelegung" do
    with_isolated_miolimos_base do
      rechnung = Invoice.create!(kind: :rechnung, creator: @hans)
      post link_invoice_path(rechnung, field: "recipient"),
           params: { create_with: "Faro GmbH", create_type: "organization" }, headers: stream
      assert_equal "organization", KnowledgeItem.find_by(title: "Faro GmbH").item_type
    end
  end

  test "Thema: ein unbekannter Kunde entsteht als Organisation" do
    with_isolated_miolimos_base do
      thema = create_topic(creator: @hans, name: "Kundenprojekt", slug: "kp-#{SecureRandom.hex(3)}")
      post set_customer_topic_path(thema), params: { create_with: "Neukunde AG" }, headers: stream
      assert_equal KnowledgeItem.find_by(title: "Neukunde AG").uuid, thema.reload.customer_uuid
    end
  end

  test "Aufgaben-Kontakte: dieselbe Namenszerlegung, und eine Organisation auf Wunsch" do
    with_isolated_miolimos_base do
      aufgabe = create_task(creator: @hans, title: "Angebot einholen")
      post "/tasks/#{aufgabe.id}/mentions", params: { create_with: "Berta von Suttner" }, headers: stream
      person = KnowledgeItem.find_by(title: "Berta von Suttner")
      assert_equal ["Berta von", "Suttner"], [person.first_name, person.last_name]

      post "/tasks/#{aufgabe.id}/mentions", params: { create_with: "Druckerei Nord", create_type: "organization" }, headers: stream
      assert_equal "organization", KnowledgeItem.find_by(title: "Druckerei Nord").item_type
      assert_equal 2, TaskMention.where(task: aufgabe).count
    end
  end

  # Wer zuordnen darf, aber keine Wissens-Einträge anlegen, bekommt keine
  # Fehlerseite mitten im Formular — es bleibt beim alten Verhalten.
  test "ohne Anlege-Recht: keine Fehlerseite, nichts angelegt" do
    with_isolated_miolimos_base do
      brief = Document.create!(kind: :brief, creator: @hans)
      grant(@hans, "KnowledgeItem", %w[read update])   # ohne „create"
      assert_no_difference -> { KnowledgeItem.count } do
        post link_document_path(brief, field: "issuer"), params: { create_with: "Darf Nicht GmbH" }, headers: stream
      end
      assert_response :success
      assert_nil brief.reload.issuer_uuid
    end
  end

  test "das Auswahlfeld traegt die Arten und ihre Beschriftung" do
    brief = Document.create!(kind: :brief, creator: @hans)
    get "/documents/#{brief.id}/card"
    assert_response :success
    assert_includes response.body, "data-entity-picker-create-types-value"
    assert_includes response.body, I18n.t("kontakt_anlegen.organisation")
  end

  # ── Personen-Picker im Formular (aus immoOS #1661/#1662) ────────────────

  test "Schnellanlage antwortet dem Picker als JSON mit der Kennung — der getippte Name wird der Titel" do
    with_isolated_miolimos_base do
      post "/knowledge_items",
           params: { quick_create: "1", item_type: "person", title: "Emma Roth", first_name: "Emma", last_name: "Roth" },
           headers: { "Accept" => "application/json" }
      assert_response :success
      antwort = JSON.parse(response.body)
      person  = KnowledgeItem.find(antwort["uuid"])
      assert_equal ["Emma Roth", "person"], [antwort["title"], antwort["item_type"]]
      assert_equal ["Emma", "Roth"], [person.first_name, person.last_name]
    end
  end

  # #1662: Die Kennung trägt die Verbindung — sie überlebt eine Umbenennung und
  # unterscheidet zwei gleichnamige Kontakte. Der Name bleibt der Rückfall.
  test "Beziehung: die Kennung aus dem Picker gewinnt gegen den Namen" do
    with_isolated_miolimos_base do
      anna   = FileProxy.create(actor: @hans, title: "Anna Bergmann", item_type: :person, content: "")
      erste  = FileProxy.create(actor: @hans, title: "Max Meier", item_type: :person, content: "")
      zweite = FileProxy.create(actor: @hans, title: "Max Meier", item_type: :person, content: "")

      patch "/knowledge_items/#{anna.uuid}",
            params: { relationships: [{ to: "Max Meier", to_uuid: zweite.uuid, kind: "Kolleg:in" }] },
            headers: stream
      assert_response :success
      assert_equal [zweite.uuid], Relationship.where(from_uuid: anna.uuid).pluck(:to_uuid),
                   "bei zwei gleichnamigen Kontakten entschied der Zufall (erster Treffer am Namen: #{erste.uuid[0, 8]})"
    end
  end

  test "Beziehungs-Editor: Picker statt der Namensliste aller Kontakte" do
    with_isolated_miolimos_base do
      anna = FileProxy.create(actor: @hans, title: "Anna Bergmann", item_type: :person, content: "")
      get "/knowledge_items/#{anna.uuid}/card"
      assert_response :success
      assert_includes response.body, 'data-controller="person-picker"'
      refute_includes response.body, "rel-suggestions-", "die datalist mit ALLEN Kontaktnamen ist entfallen"
    end
  end

  # Beim Übernehmen gefunden: Auch die Vorschlagslisten der Nachbar-Editoren
  # (Identifier-Gegenpartei, Mutter-Organisation) betteten die Namen ALLER
  # Kontakte in jede Personen-Card ein — ohne Sichtbarkeitsfilter (#602).
  test "die Vorschlagslisten einer Personen-Card nennen einem Mitglied keine fremden Kontakte" do
    with_isolated_miolimos_base do
      mia = create_human(name: "Mia Member", role: :member, password: "secretsecret")
      CapabilityDefaults.grant_full!(mia)
      FileProxy.create(actor: @hans, title: "Geheimer Investor", item_type: :person, content: "")
      FileProxy.create(actor: @hans, title: "Geheime Holding AG", item_type: :organization, content: "")
      delete "/logout"
      post "/login", params: { email: mia.email, password: "secretsecret" }
      eigene = FileProxy.create(actor: mia, title: "Mias Kontakt", item_type: :person, content: "")

      get "/knowledge_items/#{eigene.uuid}/card"
      assert_response :success
      refute_includes response.body, "Geheimer Investor"
      refute_includes response.body, "Geheime Holding AG"
    end
  end
end