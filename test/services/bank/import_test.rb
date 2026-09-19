require "test_helper"

# #1337 Schnitt 3: die Importwege. Geprüft wird, was im immoOS-Fork im Betrieb
# schiefgegangen ist — Doppelimport, Datumsfallen, Vorzeichen, und die
# Saldo-Prüfsumme beim PDF, ohne die ein still verlorener Umsatz erst auffällt,
# wenn eine Abrechnung nicht stimmt.
class Bank::ImportTest < ActiveSupport::TestCase
  setup do
    @konto = BankLedger.create!(label: "Geschäftskonto", iban: "DE89370400440532013000")
  end

  CAMT = <<~XML.freeze
    <?xml version="1.0" encoding="UTF-8"?>
    <Document xmlns="urn:iso:std:iso:20022:tech:xsd:camt.053.001.02">
      <BkToCstmrStmt><Stmt>
        <Acct><Id><IBAN>DE89370400440532013000</IBAN></Id><Ownr><Nm>Muster GmbH</Nm></Ownr></Acct>
        <Ntry>
          <Amt Ccy="EUR">119.00</Amt><CdtDbtInd>DBIT</CdtDbtInd>
          <BookgDt><Dt>2026-03-02</Dt></BookgDt><ValDt><Dt>2026-03-01</Dt></ValDt>
          <AcctSvcrRef>REF-1</AcctSvcrRef>
          <NtryDtls><TxDtls>
            <RltdPties><Cdtr><Nm>Stadtwerke</Nm></Cdtr>
              <CdtrAcct><Id><IBAN>DE02120300000000202051</IBAN></Id></CdtrAcct></RltdPties>
            <RmtInf><Ustrd>Abschlag Strom</Ustrd></RmtInf>
          </TxDtls></NtryDtls>
        </Ntry>
        <Ntry>
          <Amt Ccy="EUR">500.00</Amt><CdtDbtInd>CRDT</CdtDbtInd>
          <BookgDt><Dt>2026-03-05</Dt></BookgDt>
          <AcctSvcrRef>REF-2</AcctSvcrRef>
          <NtryDtls><TxDtls><RmtInf><Ustrd>Eingang</Ustrd></RmtInf></TxDtls></NtryDtls>
        </Ntry>
      </Stmt></BkToCstmrStmt>
    </Document>
  XML

  CSV = <<~CSV.freeze
    Umsatzliste Konto DE89 3704 0044 0532 0130 00
    Buchungstag;Wertstellung;Verwendungszweck;Beguenstigter;IBAN;Betrag
    02.03.2026;01.03.2026;Abschlag Strom;Stadtwerke;DE02120300000000202051;-119,00
    05.03.2026;05.03.2026;Eingang;Kunde AG;DE02120300000000202052;500,00
  CSV

  # ── CAMT ──────────────────────────────────────────────────────────────

  test "CAMT: Vorzeichen aus CdtDbtInd, Gegenpartei und Zweck" do
    ergebnis = Bank::Import.call(@konto, CAMT, filename: "auszug.xml")
    assert_equal :camt, ergebnis.format
    assert_equal 2, ergebnis.imported

    aus = @konto.bank_transactions.find_by(bank_ref: "REF-1")
    assert_equal BigDecimal("-119"), aus.amount, "DBIT = Auszahlung = negativ"
    assert_equal Date.new(2026, 3, 2), aus.booked_on
    assert_equal Date.new(2026, 3, 1), aus.value_date
    assert_equal "Stadtwerke", aus.counterparty_name
    assert_equal "DE02120300000000202051", aus.counterparty_iban
    assert_equal "Abschlag Strom", aus.purpose
    assert aus.camt?

    assert @konto.bank_transactions.find_by(bank_ref: "REF-2").deposit?
  end

  test "CAMT: das Konto des Auszugs wird erkannt, nicht die Gegenpartei" do
    d = Bank::Import.detect(CAMT)
    assert_equal :camt, d.format
    assert_equal "DE89370400440532013000", d.account_iban
    assert_equal "Muster GmbH", d.account_name
    assert_equal 2, d.entry_count
    assert_equal @konto, d.ledger
    assert d.sicher?
  end

  # ── CSV ───────────────────────────────────────────────────────────────

  test "CSV: Präambel wird übersprungen, deutsches Zahlen- und Datumsformat" do
    ergebnis = Bank::Import.call(@konto, CSV, filename: "umsaetze.csv")
    assert_equal :csv, ergebnis.format
    assert_equal 2, ergebnis.imported

    aus = @konto.bank_transactions.find_by(amount: -119)
    assert_equal Date.new(2026, 3, 2), aus.booked_on
    assert_equal "Stadtwerke", aus.counterparty_name
    assert aus.csv?
  end

  test "CSV: die Konto-IBAN wird aus der Präambel gelesen" do
    assert_equal "DE89370400440532013000", Bank::Import.detect(CSV).account_iban
  end

  # ── Doppelimport ──────────────────────────────────────────────────────

  # Ein Auszug wird garantiert zweimal importiert — von Hand, nach einem
  # Abbruch, oder weil sich Zeiträume überlappen.
  test "derselbe Auszug zweimal importiert legt nichts doppelt an" do
    Bank::Import.call(@konto, CAMT)
    zweite = Bank::Import.call(@konto, CAMT)

    assert_equal 0, zweite.imported
    assert_equal 2, zweite.skipped
    assert_equal 2, @konto.bank_transactions.count
    assert_nil zweite.statement, "ein reiner Doppelimport erzeugt keinen leeren Auszug"
  end

  # Ohne laufende Nummer über den ganzen Auszug hinweg bekämen zwei identische
  # Zeilen denselben Fingerprint — die zweite fiele beim ERSTEN Import weg.
  test "zwei identische Zeilen ohne Referenz sind zwei Umsätze, beim zweiten Mal keiner" do
    doppelt = <<~CSV
      Buchungstag;Verwendungszweck;Betrag
      02.03.2026;Kontoführung;-4,90
      02.03.2026;Kontoführung;-4,90
    CSV
    erste = Bank::Import.call(@konto, doppelt)
    assert_equal 2, erste.imported, "zwei echte Buchungen, nicht eine"

    zweite = Bank::Import.call(@konto, doppelt)
    assert_equal 0, zweite.imported
    assert_equal 2, zweite.skipped, "der erneute Import erkennt beide als Duplikat"
  end

  # #1675: Deutsche Banken schreiben in <AcctSvcrRef> gern den Platzhalter
  # NONREF. Die Ausnahmeliste kannte nur NOTPROVIDED — alle NONREF-Umsätze
  # bekamen denselben Fingerabdruck „ref:NONREF", der erste wurde importiert,
  # die übrigen galten als Dubletten („1 importiert, 40 übersprungen").
  def camt_mit(*eintraege)
    ntry = eintraege.map do |e|
      ref = e[:ref] ? "<AcctSvcrRef>#{e[:ref]}</AcctSvcrRef>" : ""
      e2e = e[:e2e] ? "<Refs><EndToEndId>#{e[:e2e]}</EndToEndId></Refs>" : ""
      <<~N
        <Ntry>
          <Amt Ccy="EUR">#{e[:betrag]}</Amt><CdtDbtInd>CRDT</CdtDbtInd>
          <BookgDt><Dt>#{e[:am]}</Dt></BookgDt>#{ref}
          <NtryDtls><TxDtls>#{e2e}<RmtInf><Ustrd>#{e[:zweck]}</Ustrd></RmtInf></TxDtls></NtryDtls>
        </Ntry>
      N
    end.join
    <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <Document xmlns="urn:iso:std:iso:20022:tech:xsd:camt.053.001.02">
        <BkToCstmrStmt><Stmt>#{ntry}</Stmt></BkToCstmrStmt>
      </Document>
    XML
  end

  test "CAMT: der Platzhalter NONREF ist keine Referenz — jeder Umsatz zaehlt" do
    auszug = camt_mit({ ref: "NONREF", betrag: "850.00", am: "2026-03-02", zweck: "Miete Meier" },
                      { ref: "NONREF", betrag: "920.00", am: "2026-03-02", zweck: "Miete Schulz" },
                      { ref: "nonref", betrag: "40.00",  am: "2026-03-03", zweck: "Nachzahlung" })
    erste = Bank::Import.call(@konto, auszug)
    assert_equal 3, erste.imported, "drei Umsätze — NONREF hat zwei davon verschluckt"
    assert_equal 0, erste.skipped

    zweite = Bank::Import.call(@konto, auszug)
    assert_equal [0, 3], [zweite.imported, zweite.skipped], "der Doppelimport bleibt erkannt"
  end

  # Die EndToEndId vergibt der ZAHLER. Ein Dauerauftrag trägt jeden Monat
  # dieselbe — als „eindeutige Bankreferenz" genommen, fiel er ab dem zweiten
  # Monat als Dublette weg.
  test "CAMT: dieselbe EndToEndId in zwei Monaten sind zwei Umsaetze" do
    maerz = camt_mit({ e2e: "DAUERAUFTRAG-MIETE", betrag: "850.00", am: "2026-03-02", zweck: "Miete" })
    april = camt_mit({ e2e: "DAUERAUFTRAG-MIETE", betrag: "850.00", am: "2026-04-02", zweck: "Miete" })

    assert_equal 1, Bank::Import.call(@konto, maerz).imported
    assert_equal 1, Bank::Import.call(@konto, april).imported, "der April-Eingang wurde als Dublette verworfen"
    assert_equal 0, Bank::Import.call(@konto, april).imported, "derselbe Auszug noch einmal bleibt eine Dublette"
    assert_equal "DAUERAUFTRAG-MIETE", @konto.bank_transactions.last.bank_ref, "die Referenz bleibt zur Ansicht erhalten"
  end

  # Bestand aus der Zeit davor trägt den Fingerabdruck „ref:<EndToEndId>".
  # Derselbe Auszug, neu eingelesen, darf ihn nicht ein zweites Mal anlegen.
  test "CAMT: ein nach alter Regel importierter Umsatz wird beim Neu-Import wiedererkannt" do
    @konto.bank_transactions.create!(booked_on: Date.new(2026, 3, 2), amount: 850, currency: "EUR",
                                     purpose: "Miete", bank_ref: "DAUERAUFTRAG-MIETE",
                                     fingerprint: "ref:DAUERAUFTRAG-MIETE", source: "camt")
    maerz = camt_mit({ e2e: "DAUERAUFTRAG-MIETE", betrag: "850.00", am: "2026-03-02", zweck: "Miete" })

    ergebnis = Bank::Import.call(@konto, maerz)
    assert_equal [0, 1], [ergebnis.imported, ergebnis.skipped]
  end

  # #1675: Eine Zeile mit unlesbarem Betrag fiel beim Import UNGEZÄHLT weg —
  # „3 neu, 0 bereits vorhanden", und niemand erfuhr von der vierten.
  test "CSV: eine Zeile mit unlesbarem Betrag wird gezaehlt, nicht verschwiegen" do
    csv = <<~CSV
      Buchungstag;Verwendungszweck;Betrag
      02.03.2026;Miete;850,00
      03.03.2026;Kontoführung;4,90-
      04.03.2026;Kaputt;zwölf Euro
    CSV
    ergebnis = Bank::Import.call(@konto, csv)
    assert_equal 2, ergebnis.imported
    assert_equal 1, ergebnis.unlesbar, "die unlesbare Zeile muss im Ergebnis stehen"
    assert_equal [850, -4.9].map(&:to_d), @konto.bank_transactions.order(:booked_on).pluck(:amount)
  end

  # Manche Exporte führen den Betrag OHNE Vorzeichen und daneben eine Spalte
  # Soll/Haben. Die Kopfzeilen-Erkennung hielt „Soll/Haben" selbst für die
  # Betragsspalte oder las den Betrag als positiv — Abbuchungen als Eingänge.
  test "CSV: Betrag ohne Vorzeichen plus Soll/Haben-Spalte ergibt das richtige Vorzeichen" do
    csv = <<~CSV
      Buchungstag;Verwendungszweck;Umsatz;Soll/Haben
      02.03.2026;Miete Meier;850,00;H
      03.03.2026;Stadtwerke;119,00;S
    CSV
    Bank::Import.call(@konto, csv)
    assert_equal [850, -119].map(&:to_d), @konto.bank_transactions.order(:booked_on).pluck(:amount)
  end

  # ── Auszug als Herkunft ───────────────────────────────────────────────

  test "der Auszug hält Zeitraum und Zählung und nimmt seine Umsätze mit" do
    ergebnis = Bank::Import.call(@konto, CAMT, filename: "maerz.xml")
    auszug = ergebnis.statement

    assert_equal "maerz.xml", auszug.filename
    assert_equal "camt", auszug.format
    assert_equal 2, auszug.entry_count
    assert_equal Date.new(2026, 3, 2), auszug.period_from
    assert_equal Date.new(2026, 3, 5), auszug.period_to
    assert_equal 2, auszug.bank_transactions.count

    assert_difference -> { BankTransaction.count }, -2 do
      auszug.revert!
    end
  end

  # ── Datumsfallen ──────────────────────────────────────────────────────

  test "ein unmögliches Datum wird nicht geraten, sondern verworfen" do
    assert_nil Bank::Datum.parse("30.02.2026")
    assert_nil Bank::Datum.parse("2026-13-01")
    assert_nil Bank::Datum.parse("Kontoauszug")
    assert_equal Date.new(2026, 3, 2), Bank::Datum.parse("02.03.2026")
    assert_equal Date.new(2026, 3, 2), Bank::Datum.parse("2026-03-02")
    assert_equal Date.new(2026, 3, 2), Bank::Datum.parse("2.3.26")
  end

  # Auf dem Auszug IST der 30.02. eine Wertstellungskonvention — dort darf die
  # Zeile nicht verlorengehen, sie gehört ans Monatsende.
  test "im Auszug wird der 30.02. ans Monatsende geklemmt" do
    assert_equal Date.new(2026, 2, 28), Bank::Datum.im_monat("30.02.", 2026)
    assert_equal Date.new(2024, 2, 29), Bank::Datum.im_monat("30.02.", 2024), "Schaltjahr"
    assert_nil   Bank::Datum.im_monat("01.13.", 2026)
    assert_nil   Bank::Datum.im_monat("", 2026)
  end

  test "eine CSV-Zeile mit unmöglichem Datum verliert das Datum, nicht den Umsatz" do
    kaputt = <<~CSV
      Buchungstag;Verwendungszweck;Betrag
      30.02.2026;Kontoführung;-4,90
    CSV
    assert_equal 1, Bank::Import.call(@konto, kaputt).imported
    assert_nil @konto.bank_transactions.sole.booked_on,
               "lieber ohne Datum als mit einem erfundenen"
  end
end
