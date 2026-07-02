require "test_helper"

# #625 (Hans, 2026-06-14): Überweisungs-Formular → GiroCode.
class GiroCodesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @hans = HumanActor.create!(
      name: "Hans", email: "hans-giro-#{SecureRandom.hex(3)}@t.local",
      password: "secretsecret"
    )
    grant(@hans, "KnowledgeItem", %w[read create update delete])
    post "/login", params: { email: @hans.email, password: "secretsecret" }
  end

  def make_contact(title, type)
    KnowledgeItem.create!(
      uuid: SecureRandom.uuid, title: title, item_type: type, creator: @hans,
      file_path: "ki/giro-#{SecureRandom.hex(4)}.md",
      content_hash: SecureRandom.hex(8)
    )
  end

  test "Formular listet nur Kontakte mit hinterlegter IBAN" do
    with = make_contact("Giro-Empfaenger AG", :organization)
    Identifier.create!(knowledge_item: with, label: "IBAN", value: "DE14120300001054082779")
    make_contact("Ohne-Konto GmbH", :organization)

    get "/ueberweisung"
    assert_response :success
    assert_includes @response.body, "Giro-Empfaenger AG"
    refute_includes @response.body, "Ohne-Konto GmbH"
  end

  test "Kontakt + Betrag + Zweck rendert GiroCode-SVG mit IBAN" do
    ki = make_contact("Zahlungsempfaenger", :person)
    Identifier.create!(knowledge_item: ki, label: "IBAN", value: "DE14120300001054082779")

    get "/ueberweisung", params: { contact_uuid: ki.uuid, amount: "49,90", purpose: "Rechnung 2026-1" }
    assert_response :success
    assert_includes @response.body, "crispEdges" # QR-SVG (rqrcode) vorhanden
    assert_includes @response.body, "DE14120300001054082779"
    assert_includes @response.body, "Rechnung 2026-1"
  end

  test "Kontakt ohne IBAN zeigt IBAN-Eingabefeld statt Fehler" do
    ki = make_contact("Kein-IBAN Person", :person)
    get "/ueberweisung", params: { contact_uuid: ki.uuid }
    assert_response :success
    assert_includes @response.body, 'name="iban"'        # editierbares IBAN-Feld
    assert_includes @response.body, "noch keine IBAN hinterlegt"
    refute_includes @response.body, "crispEdges"          # kein QR ohne IBAN
  end

  test "getippte IBAN (params) rendert QR auch ohne hinterlegte" do
    ki = make_contact("Neu-IBAN Person", :person)
    get "/ueberweisung", params: { contact_uuid: ki.uuid, iban: "DE14120300001054082779" }
    assert_response :success
    assert_includes @response.body, "crispEdges"
    # bietet das Hinterlegen an
    assert_includes @response.body, "hinterlegen"
  end

  test "save_iban legt IBAN als Identifier am Kontakt an" do
    ki = make_contact("Hinterleg Person", :person)
    assert_nil ki.identifiers.find { |i| i.label.casecmp?("IBAN") }
    post "/ueberweisung/iban", params: { contact_uuid: ki.uuid, iban: "DE14 1203 0000 1054 0827 79" }
    assert_response :redirect
    idf = ki.reload.identifiers.find { |i| i.label.casecmp?("IBAN") }
    assert idf, "IBAN-Identifier sollte angelegt sein"
    assert_equal "DE14120300001054082779", idf.value # normalisiert (ohne Leerzeichen)
  end

  test "save_iban aktualisiert bestehende IBAN statt zu duplizieren" do
    ki = make_contact("Update Person", :person)
    Identifier.create!(knowledge_item: ki, label: "IBAN", value: "DE00000000000000000000")
    post "/ueberweisung/iban", params: { contact_uuid: ki.uuid, iban: "DE14120300001054082779" }
    assert_response :redirect
    ibans = ki.reload.identifiers.select { |i| i.label.casecmp?("IBAN") }
    assert_equal 1, ibans.size
    assert_equal "DE14120300001054082779", ibans.first.value
  end
end
