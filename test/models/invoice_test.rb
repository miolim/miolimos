require "test_helper"

# #926: Invoice = Rechnung/Angebot als eigene strukturierte Entität —
# Positionen, Beträge, EN16931-Steueraufschlüsselung, Nummernkreis.
class InvoiceTest < ActiveSupport::TestCase
  test "kind/status enums" do
    assert Invoice.new(kind: :rechnung).rechnung?
    assert Invoice.new(kind: :angebot).angebot?
    assert_equal "entwurf", Invoice.new(kind: :rechnung).status
  end

  test "invoice_line berechnet Netto/Steuer/Brutto" do
    l = InvoiceLine.new(quantity: 12, unit_price: 120, tax_rate: 19)
    assert_equal 1440, l.net
    assert_in_delta 273.6, l.tax_amount, 0.001
    assert_in_delta 1713.6, l.gross, 0.001
  end

  test "summiert Beträge und liefert EN16931-Steueraufschlüsselung" do
    invoice = Invoice.create!(kind: :rechnung)
    invoice.invoice_lines.create!(description: "Beratung", quantity: 10, unit_price: 100, tax_rate: 19)
    invoice.invoice_lines.create!(description: "Auslagen", quantity: 1, unit_price: 90,  tax_rate: 19)
    invoice.invoice_lines.create!(description: "Buch",     quantity: 1, unit_price: 50,  tax_rate: 7)
    invoice.reload

    assert_equal 1140, invoice.net_total            # 1000 + 90 + 50
    # 19%: 1090 net -> 207.1 ; 7%: 50 net -> 3.5
    assert_in_delta 210.6, invoice.tax_total, 0.001
    assert_in_delta 1350.6, invoice.gross_total, 0.001

    bd = invoice.tax_breakdown
    assert_equal [7, 19], bd.map { |g| g[:rate].to_i }
    g7  = bd.find { |g| g[:rate].to_i == 7 }
    g19 = bd.find { |g| g[:rate].to_i == 19 }
    assert_equal 50, g7[:net]
    assert_in_delta 3.5, g7[:tax], 0.001
    assert_equal 1090, g19[:net]
    assert_in_delta 207.1, g19[:tax], 0.001
  end

  # #541: Nummernkreis "YYYY-NNN" pro Aussteller und Jahr.
  test "next_number zählt pro Aussteller fortlaufend" do
    uuid_a = SecureRandom.uuid
    uuid_b = SecureRandom.uuid
    year   = Date.current.year
    Invoice.create!(kind: :rechnung, issuer_uuid: uuid_a, number: "#{year}-003")
    Invoice.create!(kind: :rechnung, issuer_uuid: uuid_b, number: "#{year}-011")
    assert_equal "#{year}-004", Invoice.next_number(uuid_a)
    assert_equal "#{year}-012", Invoice.next_number(uuid_b)
    assert_equal "#{year}-001", Invoice.next_number(SecureRandom.uuid)
    assert_nil Invoice.next_number(nil)
  end

  # #941: eingehende Rechnungen zählen NICHT in den Nummernkreis — deren
  # Nummer stammt vom fremden Aussteller.
  test "next_number ignoriert eingehende Rechnungen" do
    uuid = SecureRandom.uuid
    year = Date.current.year
    Invoice.create!(kind: :rechnung, direction: :eingehend, issuer_uuid: uuid, number: "#{year}-950")
    assert_equal "#{year}-001", Invoice.next_number(uuid)
  end

  test "display_name = Aussteller · Nummer · Datum" do
    ki = KnowledgeItem.create!(uuid: SecureRandom.uuid, title: "Firma GmbH", item_type: :organization,
                               file_path: "kb/#{SecureRandom.hex(4)}.md", content_hash: SecureRandom.hex(8))
    invoice = Invoice.create!(kind: :rechnung, issuer_uuid: ki.uuid, number: "2026-042",
                              document_date: Date.new(2026, 7, 9))
    assert_equal "Firma GmbH · 2026-042 · 09.07.2026", invoice.display_name
  end

  # #926: Artefakte + Felder laufen über die polymorphe Schicht.
  test "document_fields und document_artifacts hängen polymorph an der Invoice" do
    invoice = Invoice.create!(kind: :rechnung)
    invoice.document_fields.create!(label: "Bestellnr", value: "B-77", position: 0)
    art = invoice.document_artifacts.create!(pdf: "PDFBYTES", signed: false)
    assert_equal "Invoice", art.printable_type
    assert_equal [["Bestellnr", "B-77"]], invoice.info_fields
    assert_equal "B-77", invoice.merge_context["bestellnr"]
  end
end
