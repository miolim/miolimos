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
end
