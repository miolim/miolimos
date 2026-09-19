require "test_helper"

# #564: Compliance-Strecke einfrieren — die e-Rechnung (EN16931) ist die
# regulatorisch heikelste Ausgabe des Systems. payload() ist reines Ruby
# (immer getestet); die XML-Erzeugung läuft nur, wenn das venv da ist
# (auf der Box ja; anderswo skip statt rot).
class ZugferdGeneratorTest < ActiveSupport::TestCase
  setup do
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
    # #926: die e-Rechnung hängt an der Invoice-Entität (vorher Document).
    @doc = Invoice.create!(kind: :rechnung, number: "2026-042", status: :entwurf,
                           issuer_uuid: @issuer.uuid, recipient_uuid: @recipient.uuid,
                           document_date: Date.new(2026, 6, 10),
                           service_start: Date.new(2026, 5, 1), service_end: Date.new(2026, 5, 31))
    @doc.invoice_lines.create!(description: "Beratung", quantity: 2, unit: "Std",
                               unit_price: 50, tax_rate: 19, position: 0)
  end

  test "payload: Adresse, Leistungszeitraum, Einheiten-Mapping, Beträge" do
    p = ZugferdGenerator.payload(@doc)
    assert_equal "Musterweg 1", p[:seller][:line1]
    assert_equal "DE",          p[:seller][:country]   # "Deutschland" -> ISO
    assert_equal "2026-05-01",  p[:service_start]
    assert_equal "2026-05-31",  p[:service_end]
    assert_equal "HUR",         p[:lines][0][:unit]    # "Std" -> Stunden
    assert_equal "100.00",      p[:net_total]
    assert_equal "19.00",       p[:tax_total]
    assert_equal "119.00",      p[:gross_total]
    assert_equal [{ rate: "19.00", net: "100.00", tax: "19.00" }], p[:tax_breakdown]
  end

  # #1675: Die XML-Beträge liefen über Fließkomma (`format("%.2f", v.to_f)`
  # rundet 64,125 auf 64,12), das Brutto über Dezimalrechnung (rundet auf).
  # 0,75 h × 85,50 € bei 19 %: Netto 64,12 + Steuer 12,18 = 76,30, aber Brutto
  # 76,31 — das verletzt BR-CO-15, ein validierender Empfänger (Behörden-Portal)
  # weist die Rechnung ab, und das PDF zeigte 64,13. Alle Tests rechneten 2 × 50.
  # Viertelstunden-Abrechnung trifft das regelmäßig.
  test "payload: Betraege sind auch bei krummen Stunden in sich stimmig (BR-CO-10/13/15/17)" do
    @doc.invoice_lines.destroy_all
    @doc.invoice_lines.create!(description: "Beratung", quantity: "0.75", unit: "Std",
                               unit_price: "85.50", tax_rate: 19, position: 0)
    @doc.invoice_lines.create!(description: "Workshop", quantity: "1.25", unit: "Std",
                               unit_price: "85.50", tax_rate: 19, position: 1)
    @doc.invoice_lines.create!(description: "Fachbuch", quantity: 1, unit: "Stk",
                               unit_price: "19.99", tax_rate: 7, position: 2)
    p = ZugferdGenerator.payload(@doc.reload)
    d = ->(s) { BigDecimal(s) }

    assert_equal "64.13", p[:lines][0][:net], "0,75 × 85,50 = 64,125 rundet kaufmännisch AUF"
    # BR-CO-10: Summe der Positions-Nettobeträge = Netto gesamt
    assert_equal d[p[:net_total]], p[:lines].sum { |l| d[l[:net]] }
    # BR-CO-13/17: je Steuersatz Netto × Satz, auf Cent gerundet; Summen passen
    p[:tax_breakdown].each do |g|
      assert_equal (d[g[:net]] * d[g[:rate]] / 100).round(2), d[g[:tax]], "Steuer der Gruppe #{g[:rate]} %"
    end
    assert_equal d[p[:net_total]], p[:tax_breakdown].sum { |g| d[g[:net]] }
    assert_equal d[p[:tax_total]], p[:tax_breakdown].sum { |g| d[g[:tax]] }
    # BR-CO-15: Brutto = Netto + Steuer
    assert_equal d[p[:gross_total]], d[p[:net_total]] + d[p[:tax_total]]

    # Und das Modell sagt dasselbe wie die XML — sonst zeigt das PDF andere
    # Zahlen als die eingebettete e-Rechnung.
    assert_equal d[p[:net_total]],   @doc.net_total
    assert_equal d[p[:tax_total]],   @doc.tax_total
    assert_equal d[p[:gross_total]], @doc.gross_total
  end

  test "payload: Steuernummer (ohne USt-IdNr) landet als tax_number" do
    @issuer.identifiers.where(label: "USt-IdNr").delete_all
    @issuer.identifiers.create!(label: "Steuernummer", value: "12/345/67890", position: 2)
    p = ZugferdGenerator.payload(@doc.reload)
    assert_nil p[:seller][:vat_id]
    assert_equal "12/345/67890", p[:seller][:tax_number]
  end

  test "BR-CO-26: ohne USt-IdNr UND Steuernummer klare Fehlermeldung" do
    @issuer.identifiers.delete_all
    err = assert_raises(ZugferdGenerator::Error) { ZugferdGenerator.xml(@doc.reload) }
    assert_match(/USt-IdNr oder Steuernummer/, err.message)
  end

  test "vat_exempt: keine USt im Payload" do
    @issuer.update!(vat_exempt: true)
    p = ZugferdGenerator.payload(@doc.reload)
    assert p[:vat_exempt]
    assert_equal "0.00",   p[:tax_total]
    assert_equal "100.00", p[:gross_total]
    assert_empty p[:tax_breakdown]
  end

  test "xml: erzeugt EN16931-CII mit Nummer, Verkäufer-USt-Id und Summen" do
    skip "ZUGFeRD-venv nicht vorhanden" unless ZugferdGenerator.available?
    xml = ZugferdGenerator.xml(@doc)
    doc = Nokogiri::XML(xml)
    doc.remove_namespaces!
    assert_equal "2026-042", doc.at_xpath("//ExchangedDocument/ID")&.text
    # BT-31: Verkäufer-USt-IdNr als SpecifiedTaxRegistration (Schema VA)
    assert_equal "DE123456789",
      doc.at_xpath("//SellerTradeParty//SpecifiedTaxRegistration/ID[@schemeID='VA']")&.text
    assert_equal "119.00", doc.at_xpath("//SpecifiedTradeSettlementHeaderMonetarySummation/GrandTotalAmount")&.text
    assert_equal "EUR", doc.at_xpath("//InvoiceCurrencyCode")&.text
  end
end
