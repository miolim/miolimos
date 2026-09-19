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
end
