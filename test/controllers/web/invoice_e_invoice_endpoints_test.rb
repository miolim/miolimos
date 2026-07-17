require "test_helper"

# #1055 (Lücke): Die e-Rechnungs-SERVICES sind gut getestet
# (zugferd_generator_test), aber die Controller-Endpoints hatten keine
# Assertion — hier: XML-Auslieferung, Fehlerpfad, Login-Gate. Das
# ZUGFeRD-PDF (DocumentRenderer + PDF/A-3-Anreicherung) bleibt dem
# Service-Test überlassen; hier nur sein Fehlerpfad.
class InvoiceEInvoiceEndpointsTest < ActionDispatch::IntegrationTest
  setup do
    @hans = create_human(password: "secretsecret")
    CapabilityDefaults.grant_full!(@hans)
    post "/login", params: { email: @hans.email, password: "secretsecret" }

    @issuer = KnowledgeItem.create!(uuid: SecureRandom.uuid, title: "Aussteller GmbH",
                                    item_type: :organization, file_path: "x/aussteller.md",
                                    content_hash: "h", body: "")
    @issuer.identifiers.create!(label: "USt-IdNr", value: "DE123456789", position: 0)
    @issuer.identifiers.create!(label: "IBAN", value: "DE89370400440532013000", position: 1)
    @issuer.postal_addresses.create!(line1: "Musterweg 1", postal_code: "20095",
                                     city: "Hamburg", country: "Deutschland", billing: true)
    @recipient = KnowledgeItem.create!(uuid: SecureRandom.uuid, title: "Kunde AG",
                                       item_type: :organization, file_path: "x/kunde.md",
                                       content_hash: "h", body: "")
    @invoice = Invoice.create!(kind: :rechnung, number: "2026-099", status: :entwurf,
                               issuer_uuid: @issuer.uuid, recipient_uuid: @recipient.uuid,
                               document_date: Date.new(2026, 7, 1))
    @invoice.invoice_lines.create!(description: "Beratung", quantity: 1, unit: "Std",
                                   unit_price: 100, tax_rate: 19, position: 0)
  end

  test "xrechnung_xml liefert die EN16931-XML mit Rechnungsnummer" do
    skip "XML-Toolchain (venv) fehlt auf dieser Box" unless ZugferdGenerator.available?
    get "/invoices/#{@invoice.id}/xrechnung_xml"
    assert_response :success
    assert_equal "application/xml", response.media_type
    assert_includes response.body, "2026-099"
  end

  test "xrechnung_xml ohne Steuer-Identität: 422 mit klarer Meldung statt 500" do
    @issuer.identifiers.delete_all
    get "/invoices/#{@invoice.id}/xrechnung_xml"
    assert_response :unprocessable_content
    assert_match(/USt-IdNr oder Steuernummer/, response.body)
  end

  test "zugferd_pdf ohne Steuer-Identität: 422 statt 500" do
    @issuer.identifiers.delete_all
    get "/invoices/#{@invoice.id}/zugferd_pdf"
    assert_response :unprocessable_content
  end

  test "beide Endpoints verlangen Login" do
    delete "/logout"
    get "/invoices/#{@invoice.id}/xrechnung_xml"
    assert_redirected_to %r{/login}
    get "/invoices/#{@invoice.id}/zugferd_pdf"
    assert_redirected_to %r{/login}
  end
end
