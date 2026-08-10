require "test_helper"

# #1337 Schnitt 4: die Konto-Card. Geprüft wird der Weg, den ein Mensch geht —
# Auszug hochladen, Vorschau lesen, bestätigen, zuordnen —, und vor allem, dass
# ein PDF mit nicht aufgehendem Saldo NICHT auf Knopfdruck durchrutscht.
class BankLedgersControllerTest < ActionDispatch::IntegrationTest
  setup do
    @hans = HumanActor.create!(
      name: "Hans", email: "bank-#{SecureRandom.hex(3)}@t.local",
      password: "secretsecret", role: :admin
    )
    grant(@hans, "Task",          %w[read create update delete])
    grant(@hans, "KnowledgeItem", %w[read create update delete])
    post "/login", params: { email: @hans.email, password: "secretsecret" }
    @konto = BankLedger.create!(label: "Geschäftskonto", iban: "DE89370400440532013000")
  end

  CSV = <<~CSV.freeze
    Buchungstag;Verwendungszweck;Beguenstigter;IBAN;Betrag
    02.03.2026;Abschlag Strom;Stadtwerke;DE02120300000000202051;-119,00
  CSV

  def hochladen(inhalt, name: "auszug.csv", typ: "text/csv")
    datei = Rack::Test::UploadedFile.new(StringIO.new(inhalt), typ, original_filename: name)
    post upload_bank_ledger_path(@konto), params: { file: datei },
         headers: { "Accept" => "text/vnd.turbo-stream.html" }
  end

  test "Kontenliste und Konto-Card sind erreichbar" do
    get list_card_bank_ledgers_path
    assert_response :success
    assert_includes @response.body, "Geschäftskonto"

    get card_bank_ledger_path(@konto)
    assert_response :success
    assert_includes @response.body, "Kontoauszug einlesen"
  end

  # Der Upload PRÜFT nur — geschrieben wird auf Bestätigung.
  test "Hochladen zeigt eine Vorschau und schreibt noch nichts" do
    assert_no_difference -> { BankTransaction.count } do
      hochladen(CSV)
    end
    assert_response :success
    assert_includes @response.body, "CSV"
    assert_includes @response.body, "Importieren"
  end

  test "Bestätigen legt die Umsätze an" do
    hochladen(CSV)
    assert_difference -> { BankTransaction.count }, 1 do
      post import_bank_ledger_path(@konto), headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end
    assert_response :success
    assert_equal BigDecimal("-119"), @konto.bank_transactions.sole.amount
  end

  test "ein zweiter Import derselben Datei legt nichts doppelt an" do
    hochladen(CSV)
    post import_bank_ledger_path(@konto), headers: { "Accept" => "text/vnd.turbo-stream.html" }
    hochladen(CSV)
    assert_no_difference -> { BankTransaction.count } do
      post import_bank_ledger_path(@konto), headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end
  end

  # ── Zuordnen von Hand ─────────────────────────────────────────────────

  test "Umsatz einer Zahlungspflicht zuordnen, Teilbetrag, wieder lösen" do
    beleg = Invoice.create!(kind: :rechnung, direction: :eingehend)
    beleg.invoice_lines.create!(description: "Strom", quantity: 1, unit_price: 119,
                                tax_rate: 0, position: 0)
    pflicht = beleg.reload.payment_obligations.create!(amount: -119, announced_by: beleg)
    tx = @konto.bank_transactions.create!(booked_on: Date.new(2026, 3, 2), amount: -119)

    post assign_bank_transaction_path(tx), params: { payment_obligation_id: pflicht.id, amount: "40,00" },
         headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_response :success
    assert_equal BigDecimal("-40"), pflicht.reload.settled_amount
    assert_equal :teilweise, pflicht.state

    delete unassign_bank_transaction_path(tx), headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_equal BigDecimal("0"), pflicht.reload.settled_amount
  end

  test "bewusst ohne Zuordnung setzen und zurücknehmen" do
    tx = @konto.bank_transactions.create!(booked_on: Date.new(2026, 3, 2), amount: -4.90,
                                          purpose: "Kontoführung")

    post no_assignment_bank_transaction_path(tx), params: { note: "Kontoführungsentgelt" },
         headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert tx.reload.no_assignment?
    assert_equal "Kontoführungsentgelt", tx.no_assignment_note

    post no_assignment_bank_transaction_path(tx), headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_not tx.reload.no_assignment?
  end

  # ── Die Sicherung, um die es geht ─────────────────────────────────────

  # Ein PDF, dessen Saldo nicht aufgeht, darf nicht auf Knopfdruck durchrutschen
  # — und wenn doch, muss man es dem Auszug später ansehen.
  test "PDF mit nicht aufgehendem Saldo wird angeboten, aber nicht importiert" do
    wort = ->(t, x, y) { %(<word xMin="#{x}" yMin="#{y}" xMax="#{x + t.length * 5}" yMax="#{y + 8}">#{t}</word>) }
    seite = [
      wort.("Bu-Tag Wert Vorgang", 130.0, 55),
      wort.("alter Kontostand vom 01.03.2026", 130.0, 70), wort.("1.000,00", 500.0, 70), wort.("H", 563.7, 70),
      wort.("02.03.", 32.0, 90), wort.("01.03.", 70.0, 90), wort.("Lastschrift", 130.0, 90),
      wort.("119,00", 500.0, 90), wort.("S", 563.7, 90),
      wort.("neuer Kontostand vom 31.03.2026", 130.0, 170), wort.("2.605,28", 500.0, 170), wort.("H", 563.7, 170)
    ].join
    pdf = %(<!-- bank-pdf ocr=false -->\n<page width="595.0" height="842.0">#{seite}</page>)

    hochladen(pdf, name: "foto.pdf", typ: "text/plain")
    assert_includes @response.body, "Saldo geht NICHT auf"
    assert_includes @response.body, "Trotzdem importieren"

    assert_no_difference -> { BankTransaction.count } do
      post import_bank_ledger_path(@konto), headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end
  end
end
