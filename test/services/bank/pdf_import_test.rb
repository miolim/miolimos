require "test_helper"

# #1337 Schnitt 3: der PDF-Weg. Der Kern ist nicht das Lesen, sondern der
# BEWEIS: Anfangssaldo + alle gelesenen Umsätze muss den Endsaldo ergeben.
#
# immoos_builder aus dem Fork-Betrieb: „Ein Handyfoto ist KEIN Importweg — die
# Texterkennung hat eine vollständige Buchungszeile verloren, und ohne
# Prüfsumme fällt das niemandem auf." Ein Erkennungsfehler bei Geld erzeugt
# keinen Fehler, sondern einen falschen Betrag.
#
# Getestet wird auf dem Zwischenformat (bbox-XML), nicht auf einer PDF-Datei:
# Damit hängt der Test nicht an pdftotext/ocrmypdf, und geprüft wird genau das,
# was die Logik ausmacht — Spaltenlesung, Jahreslogik, Prüfsumme.
class Bank::PdfImportTest < ActiveSupport::TestCase
  setup do
    @konto = BankLedger.create!(label: "Geschäftskonto", iban: "DE89370400440532013000")
  end

  # ── Hilfen zum Bauen eines Auszugs im Zwischenformat ──────────────────

  def wort(text, x, y, hoehe: 8.0, breite: 5.0)
    %(<word xMin="#{x}" yMin="#{y}" xMax="#{x + text.length * breite}" yMax="#{y + hoehe}">#{text}</word>)
  end

  # Eine Zeile im VR-Raster: Datumspaar (Spalte 30–125), Text (125–470),
  # Betrag rechtsbündig (470–562), H/S bei 563.7.
  def zeile(y, bu: nil, wert: nil, text: nil, betrag: nil, hs: nil)
    w = []
    w << wort(bu, 32.0, y)   if bu
    w << wort(wert, 70.0, y) if wert
    w << wort(text, 130.0, y) if text
    w << wort(betrag, 500.0, y) if betrag
    w << wort(hs, 563.7, y)  if hs
    w.join
  end

  def auszug(ende: "1.381,00")
    inhalt = [
      zeile(40,  text: "IBAN DE89370400440532013000"),
      zeile(55,  text: "Bu-Tag Wert Vorgang"),
      zeile(70,  text: "alter Kontostand vom 01.03.2026", betrag: "1.000,00", hs: "H"),
      zeile(90,  bu: "02.03.", wert: "01.03.", text: "Lastschrift", betrag: "119,00", hs: "S"),
      zeile(100, text: "Stadtwerke Beispielstadt"),
      zeile(110, text: "Abschlag Strom"),
      zeile(118, text: "DE02120300000000202051"),
      zeile(130, bu: "05.03.", wert: "05.03.", text: "Gutschrift", betrag: "500,00", hs: "H"),
      zeile(140, text: "Kunde AG"),
      zeile(170, text: "neuer Kontostand vom 31.03.2026", betrag: ende, hs: "H")
    ].join
    %(<!-- bank-pdf ocr=false -->\n<page width="595.0" height="842.0">#{inhalt}</page>)
  end

  # ── Erkennung und Lesung ──────────────────────────────────────────────

  test "das Layout wird erkannt, Konto und Umsätze stehen fest, ohne dass etwas geschrieben wird" do
    a = Bank::PdfImport.analyse(auszug)

    assert a.erkannt?, "VR-Layout muss an der Saldozeile und der H/S-Spalte erkannt werden"
    assert_equal "DE89370400440532013000", a.konto[:iban]
    assert_equal 2, a.rows.length
    assert_equal 0, BankTransaction.count, "Analyse schreibt nicht"
  end

  test "Beträge kommen aus der Spalte, das Vorzeichen aus H/S" do
    rows = Bank::PdfImport.analyse(auszug).rows

    assert_equal BigDecimal("-119"), rows.first[:amount], "S = Soll = Auszahlung"
    assert_equal BigDecimal("500"),  rows.last[:amount],  "H = Haben = Einzahlung"
    assert_equal Date.new(2026, 3, 2), rows.first[:booked_on]
    assert_equal Date.new(2026, 3, 1), rows.first[:value_date]
    assert_equal "Stadtwerke Beispielstadt", rows.first[:counterparty_name]
    assert_equal "DE02120300000000202051", rows.first[:counterparty_iban]
  end

  # Das Jahr steht nur im Saldo — die Buchungstage tragen bloß Tag und Monat.
  test "das Jahr kommt aus dem Anfangssaldo" do
    assert_equal 2026, Bank::PdfImport.analyse(auszug).rows.first[:booked_on].year
  end

  # ── Die Prüfsumme ─────────────────────────────────────────────────────

  test "geht der Saldo auf, ist der Auszug importierbar" do
    a = Bank::PdfImport.analyse(auszug)

    assert a.pruefung.ok?, "1.000,00 − 119,00 + 500,00 = 1.381,00"
    assert_equal BigDecimal("0"), a.pruefung.differenz
    assert a.importierbar?
  end

  # Der Fall aus dem Fork: eine Buchungszeile geht verloren, alles sieht
  # plausibel aus — und die Prüfsumme fällt darüber.
  test "stimmt der Endsaldo nicht, wird NICHT importiert" do
    kaputt = auszug(ende: "2.605,28")
    a = Bank::PdfImport.analyse(kaputt)

    assert a.erkannt?, "das Layout stimmt ja — nur die Summe nicht"
    assert_not a.pruefung.ok?
    assert_not a.importierbar?

    ergebnis = Bank::Import.call(@konto, kaputt, filename: "foto.pdf")
    assert_equal 0, ergebnis.imported, "ein falsch gelesener Betrag darf nicht in den Bestand"
    assert_nil   ergebnis.statement
    assert_equal 0, BankTransaction.count
  end

  # Erzwingen darf man — aber der Auszug trägt danach den Vermerk, sonst sieht
  # ein bewusst erzwungener Import später aus wie ein geprüfter.
  test "erzwungener Import wird am Auszug vermerkt" do
    ergebnis = Bank::Import.call(@konto, auszug(ende: "2.605,28"),
                                 filename: "foto.pdf", trotz_abweichung: true)

    assert_equal 2, ergebnis.imported
    assert_match(/Ohne Saldo-Prüfung/, ergebnis.statement.note)
  end

  test "ein unbekanntes Layout wird nicht geraten" do
    fremd = %(<!-- bank-pdf ocr=false -->\n<page width="595.0" height="842.0">) +
            zeile(50, text: "Irgendein anderer Auszug") + "</page>"
    a = Bank::PdfImport.analyse(fremd)

    assert_not a.erkannt?
    assert_empty a.rows
    assert_not a.importierbar?
  end

  # ── Der ganze Weg ─────────────────────────────────────────────────────

  test "geprüfter Auszug landet im Konto, mit Herkunft und Format" do
    ergebnis = Bank::Import.call(@konto, auszug, filename: "auszug-03.pdf")

    assert_equal :pdf, ergebnis.format
    assert_equal 2, ergebnis.imported
    assert ergebnis.pruefung.ok?
    assert_nil ergebnis.statement.note, "ein geprüfter Auszug braucht keinen Vermerk"
    assert @konto.bank_transactions.all?(&:pdf?)
    # Der „alte Kontostand" im Auszug ist der Anfangssaldo DES AUSZUGS und
    # dient der Prüfsumme; der Anfangssaldo des KONTOS ist die
    # Bestandsübernahme und steht hier auf 0.
    assert_equal BigDecimal("381"), @konto.reload.balance, "0 + (−119,00 + 500,00)"
  end

  test "die Konto-Erkennung sagt schon vor dem Import, ob der Auszug sicher ist" do
    assert Bank::Import.detect(auszug).sicher?
    assert_not Bank::Import.detect(auszug(ende: "2.605,28")).sicher?
    assert_equal @konto, Bank::Import.detect(auszug).ledger
  end
  # ── #1675: Jahreswechsel und mehrseitige Auszüge — bisher ungetestet ────
  # Ein falsches Jahr übersteht die Saldoprüfung (die Summe stimmt ja) und
  # bucht den Umsatz ins falsche Steuerjahr.

  def seiten(*inhalte)
    kopf = %(<!-- bank-pdf ocr=false -->\n)
    kopf + inhalte.map { |i| %(<page width="595.0" height="842.0">#{i.join}</page>) }.join("\n")
  end

  def jahreswechsel_auszug
    seiten(
      [ zeile(40,  text: "IBAN DE89370400440532013000"),
        zeile(55,  text: "Bu-Tag Wert Vorgang"),
        zeile(70,  text: "alter Kontostand vom 29.12.2025", betrag: "1.000,00", hs: "H"),
        zeile(90,  bu: "30.12.", wert: "30.12.", text: "Lastschrift", betrag: "100,00", hs: "S"),
        zeile(100, text: "Stadtwerke Beispielstadt"),
        zeile(110, text: "Abschlag Dezember"),
        zeile(130, text: "Übertrag auf Blatt 2", betrag: "900,00", hs: "H"),
        # Fußzeile von Blatt 1 — gehört zu KEINEM Umsatz:
        zeile(780, text: "Volksbank Beispielstadt eG"),
        zeile(790, text: "Vorstand Max Mustermann"),
        zeile(800, text: "DE89370400440532013000") ],
      [ # Kopf von Blatt 2 — ebenfalls kein Umsatz-Text, samt der EIGENEN IBAN:
        zeile(40,  text: "Kontoauszug Blatt 2"),
        zeile(50,  text: "IBAN DE89370400440532013000"),
        zeile(70,  text: "Übertrag von Blatt 1", betrag: "900,00", hs: "H"),
        zeile(90,  bu: "02.01.", wert: "31.12.", text: "Gutschrift", betrag: "250,00", hs: "H"),
        zeile(100, text: "Kunde AG"),
        zeile(110, text: "Rechnung 2025-117"),
        zeile(140, text: "neuer Kontostand vom 05.01.2026", betrag: "1.150,00", hs: "H") ]
    )
  end

  test "Jahreswechsel: Dezember bleibt im alten Jahr, Januar springt ins neue" do
    rows = Bank::PdfImport.analyse(jahreswechsel_auszug).rows
    assert_equal [Date.new(2025, 12, 30), Date.new(2026, 1, 2)], rows.map { |r| r[:booked_on] }
  end

  test "Jahreswechsel: am 02.01. gebucht, zum 31.12. wertgestellt — die Wertstellung liegt im Vorjahr" do
    januar = Bank::PdfImport.analyse(jahreswechsel_auszug).rows.last
    assert_equal Date.new(2025, 12, 31), januar[:value_date]
  end

  test "mehrseitig: Fuss- und Kopfzeilen landen nicht im Umsatz davor" do
    dezember = Bank::PdfImport.analyse(jahreswechsel_auszug).rows.first

    assert_equal "Stadtwerke Beispielstadt", dezember[:counterparty_name]
    refute_match(/Volksbank|Vorstand|Kontoauszug|Blatt/, dezember[:purpose].to_s,
                 "die Fußzeile von Blatt 1 steht im Verwendungszweck")
    assert_nil dezember[:counterparty_iban],
               "die EIGENE IBAN aus Fuß-/Kopfzeile wurde zur Gegenpartei-IBAN"
  end

  test "mehrseitig: jede Seite geht fuer sich auf" do
    a = Bank::PdfImport.analyse(jahreswechsel_auszug)
    assert a.pruefung.seiten_ok?, "Seitenprüfung: #{a.pruefung.inspect}"
  end

  # #1271: erster Auszug eines neuen Kontos — kein Datum am Anfangssaldo, nur am
  # Ende. Dann wird von hinten gerechnet.
  test "ohne Anfangsdatum wird das Jahr vom Endsaldo aus rueckwaerts bestimmt" do
    auszug = seiten(
      [ zeile(40,  text: "IBAN DE89370400440532013000"),
        zeile(55,  text: "Bu-Tag Wert Vorgang"),
        zeile(70,  text: "alter Kontostand", betrag: "0,00", hs: "H"),
        zeile(90,  bu: "29.12.", wert: "29.12.", text: "Gutschrift", betrag: "500,00", hs: "H"),
        zeile(100, text: "Ersteinzahlung"),
        zeile(120, bu: "03.01.", wert: "03.01.", text: "Lastschrift", betrag: "50,00", hs: "S"),
        zeile(130, text: "Kontoführung"),
        zeile(160, text: "neuer Kontostand vom 05.01.2026", betrag: "450,00", hs: "H") ]
    )
    rows = Bank::PdfImport.analyse(auszug).rows
    assert_equal [Date.new(2025, 12, 29), Date.new(2026, 1, 3)], rows.map { |r| r[:booked_on] }
  end
end
