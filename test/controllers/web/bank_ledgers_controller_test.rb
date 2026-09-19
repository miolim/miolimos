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

  # #1675: Eine Zeile mit unlesbarem Betrag fiel ungezählt weg. Gezählt nützt
  # sie nur, wenn man die Zahl auch SIEHT.
  test "der Import meldet Zeilen mit unlesbarem Betrag" do
    hochladen(CSV + "03.03.2026;Kaputt;Niemand;;n/a EUR\n")
    post import_bank_ledger_path(@konto), headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_response :success
    assert_includes @response.body, I18n.t("bank.import.unreadable", count: 1)
  end

  # #1675: Der geprüfte, aber noch nicht bestätigte Auszug lag in der SESSION —
  # und die ist ein Cookie mit 4 KB. Jeder echte Auszug ist größer: Der Upload
  # endete in CookieOverflow. Alle Tests hier nutzten eine einzeilige CSV.
  test "ein Auszug in echter Groesse laesst sich hochladen und importieren" do
    zeilen = (1..400).map do |i|
      "#{format('%02d', (i % 28) + 1)}.03.2026;Rechnung 2026-#{format('%04d', i)} Kunde Nummer #{i};Kunde #{i} GmbH;DE02120300000000202051;#{i},00"
    end
    gross = "Buchungstag;Verwendungszweck;Beguenstigter;IBAN;Betrag\n" + zeilen.join("\n") + "\n"
    assert_operator gross.bytesize, :>, 30_000

    hochladen(gross)
    assert_response :success
    assert_operator cookies.to_hash.values.sum { |v| v.to_s.bytesize }, :<, 4096, "der Auszug steckt im Cookie"

    assert_difference -> { BankTransaction.count }, 400 do
      post import_bank_ledger_path(@konto), headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end
    assert_response :success
  end

  # #1677 (Fund am Deploy-Gate von v0.7.0): Das Aufräumen alter Uploads listet
  # den Ordner und sieht dann jede Datei einzeln an. Räumt dazwischen ein anderer
  # Request eine weg (zwei Uploads zur selben Zeit; im Test die parallelen
  # Worker), darf der eigene Upload nicht mit einem 500 enden.
  test "ein Upload uebersteht, dass eine alte Datei waehrend des Aufraeumens verschwindet" do
    FileUtils.mkdir_p(BankLedgersController::ABLAGE)
    verschwunden = BankLedgersController::ABLAGE.join("schon-weg-#{SecureRandom.hex(4)}").to_s
    echt = Dir.method(:glob)
    Dir.define_singleton_method(:glob) { |*a, **k, &b| echt.call(*a, **k, &b) + [ verschwunden ] }
    begin
      hochladen(CSV)
    ensure
      # Zurücksetzen, nicht entfernen: `glob` IST eine Singleton-Methode von Dir.
      Dir.define_singleton_method(:glob, echt)
    end
    assert_response :success
    assert File.exist?(BankLedgersController::ABLAGE.join(session[:bank_upload]["schluessel"]))
  end

  test "der abgelegte Auszug gehoert zu genau diesem Konto und ist nach dem Import weg" do
    anderes = BankLedger.create!(label: "Zweitkonto", iban: "DE02120300000000202051")
    hochladen(CSV)
    # Genau DIESE Datei prüfen, nicht den ganzen Ordner — die Tests laufen parallel.
    abgelegt = BankLedgersController::ABLAGE.join(session[:bank_upload]["schluessel"])
    assert File.exist?(abgelegt)
    assert_no_difference -> { BankTransaction.count } do
      post import_bank_ledger_path(anderes), headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end
    post import_bank_ledger_path(@konto), headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_equal 1, @konto.bank_transactions.count
    refute File.exist?(abgelegt), "der Auszug blieb nach dem Import liegen"
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
