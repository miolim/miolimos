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

  # #1336 Stufe 1: Belegart als eigenes Merkmal — getrennt von `kind`.
  test "document_type ist unabhängig von kind und darf leer bleiben" do
    invoice = Invoice.create!(kind: :rechnung)
    assert_nil invoice.document_type, "Bestand/Neuanlage ohne Art = nicht erfasst"

    invoice.update!(document_type: :bescheid)
    assert invoice.document_type_bescheid?
    assert invoice.rechnung?, "kind bleibt unberührt — dort hängen Nummernkreis und Rendering"
  end

  # Die Belegart wird als Name gespeichert, nicht als Zahl. Das ist die
  # Voraussetzung dafür, dass die Liste offen bleiben kann: eine weitere Art
  # braucht keine Migration, und es gibt kein Zahlen-Mapping, das zwischen
  # miolimOS und dem immoOS-Fork auseinanderlaufen könnte.
  test "Belegart steht als Name in der Datenbank, nicht als Zahl" do
    invoice = Invoice.create!(kind: :rechnung, document_type: :bescheid)
    stored = Invoice.connection.select_value(
      "SELECT document_type FROM invoices WHERE id = #{invoice.id}"
    )
    assert_equal "bescheid", stored
  end

  # Erkennung und Auswahlfeld dürfen nicht auseinanderdriften: wer eine
  # Belegart ergänzt, soll sie an EINER Stelle ergänzen.
  test "der Dokumenten-Import kennt genau die Belegarten des Modells" do
    schema_types = Inbox::Processors::DocumentImport::EXTRACTION_SCHEMA
                     .dig("properties", "doc_type", "enum")
    assert_equal Invoice::DOCUMENT_TYPES.sort, schema_types.sort
  end

  # Der Nummernkreis darf von der Belegart nicht angefasst werden: ein
  # eingehender Bescheid verbraucht keine eigene Rechnungsnummer.
  test "eingehender Beleg mit Belegart verbraucht keine Rechnungsnummer" do
    issuer = SecureRandom.uuid
    Invoice.create!(kind: :rechnung, direction: :eingehend, document_type: :bescheid,
                    issuer_uuid: issuer, number: "FREMD-4711")
    assert_equal "2026-001", Invoice.next_number(issuer, Date.new(2026, 1, 1))
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

  # #1434 (aus immoos #1195): Brutto ist ein Geldbetrag. Ohne Rundung
  # erzeugen USt-Zeilen Drittel-Cents, die Betragsspalten (scale 2) nicht —
  # dann passt kein Umsatz je exakt und die Zahlungspflicht bleibt ewig
  # „teilweise". Im Fork blieb so nach einer Ausbuchung ein unbuchbarer
  # Restbetrag stehen.
  test "gross_total rundet auf Cent" do
    inv = Invoice.create!(kind: :rechnung, direction: :eingehend)
    inv.invoice_lines.create!(description: "Leistung", quantity: 1,
                              unit_price: BigDecimal("12212.70"), tax_rate: 19, position: 0)
    inv.reload

    assert_equal BigDecimal("14533.11"), inv.gross_total
    assert_equal 2, inv.gross_total.to_s("F").split(".").last.length
  end

  # Der Fall, der es scharf macht: Die Zahlungspflicht bekommt ihren Betrag
  # aus gross_total, und die Tilgung vergleicht auf Gleichheit.
  test "eine Zahlungspflicht aus dem Bruttobetrag ist exakt tilgbar" do
    inv = Invoice.create!(kind: :rechnung, direction: :eingehend)
    inv.invoice_lines.create!(description: "Leistung", quantity: 1,
                              unit_price: BigDecimal("12212.70"), tax_rate: 19, position: 0)
    inv.reload
    pflicht = inv.payment_obligations.create!(amount: inv.gross_total * inv.obligation_sign)

    konto = BankLedger.create!(label: "Konto")
    tx = konto.bank_transactions.create!(booked_on: Date.current, amount: -inv.gross_total)

    assert Bank::ObligationMatch.assign(tx, pflicht)
    assert_equal :bezahlt, pflicht.reload.state, "kein unbuchbarer Restbetrag"
    assert_equal BigDecimal("0"), pflicht.open_amount
  end
end
