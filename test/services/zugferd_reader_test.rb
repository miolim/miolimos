require "test_helper"

# #934: ZUGFeRD-Extraktion für Eingangsrechnungen — Roundtrip gegen den
# eigenen Generator (läuft nur mit venv; anderswo skip) + nil-Pfad.
class ZugferdReaderTest < ActiveSupport::TestCase
  test "Roundtrip: generierte ZUGFeRD-PDF wird vollständig zurückgelesen" do
    skip "ZUGFeRD-venv nicht vorhanden" unless ZugferdReader.available?

    issuer = KnowledgeItem.create!(uuid: SecureRandom.uuid, title: "Aussteller GmbH",
                                   item_type: :organization, file_path: "x/a-#{SecureRandom.hex(3)}.md",
                                   content_hash: "h", body: "")
    issuer.identifiers.create!(label: "USt-IdNr", value: "DE123456789", position: 0)
    issuer.identifiers.create!(label: "IBAN", value: "DE89370400440532013000", position: 1)
    recipient = KnowledgeItem.create!(uuid: SecureRandom.uuid, title: "Kunde AG",
                                      item_type: :organization, file_path: "x/k-#{SecureRandom.hex(3)}.md",
                                      content_hash: "h", body: "")
    invoice = Invoice.create!(kind: :rechnung, number: "2026-077",
                              issuer_uuid: issuer.uuid, recipient_uuid: recipient.uuid,
                              document_date: Date.new(2026, 6, 10),
                              service_start: Date.new(2026, 5, 1), service_end: Date.new(2026, 5, 31))
    invoice.invoice_lines.create!(description: "Beratung", quantity: 2, unit: "Std",
                                  unit_price: 50, tax_rate: 19, position: 0)

    visible = DocumentPdf.render("<html><body><h1>Rechnung</h1></body></html>")
    bytes   = ZugferdGenerator.zugferd_pdf(invoice, visible)

    Dir.mktmpdir do |dir|
      path = File.join(dir, "eingang.pdf")
      File.binwrite(path, bytes)
      data = ZugferdReader.extract(path)

      assert_equal "2026-077", data["number"]
      assert_equal "2026-06-10", data["issue_date"]
      assert_equal "Aussteller GmbH", data.dig("seller", "name")
      assert_equal "DE123456789", data.dig("seller", "vat_id")
      assert_equal "Kunde AG", data.dig("buyer", "name")
      assert_equal "2026-05-01", data["service_start"]
      assert_in_delta 119.0, data["gross_total"], 0.001
      assert_equal "DE89370400440532013000", data["iban"]
      assert_equal 1, data["lines"].size
      assert_equal "Beratung", data["lines"][0]["description"]
      assert data["due_date"].present?, "Fälligkeit (BT-9) muss gelesen werden"
    end
  end

  test "extract liefert nil für PDFs ohne eingebettete XML" do
    skip "ZUGFeRD-venv nicht vorhanden" unless ZugferdReader.available?
    visible = DocumentPdf.render("<html><body>Nur ein Brief</body></html>")
    Dir.mktmpdir do |dir|
      path = File.join(dir, "plain.pdf")
      File.binwrite(path, visible)
      assert_nil ZugferdReader.extract(path)
    end
  end
end
