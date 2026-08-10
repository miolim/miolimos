# #1337 Schnitt 3 (aus immoOS #1263): Kontoauszug-Import auch für PDF-Auszüge.
#
# PDF ist hier der dritte Parser neben CAMT und CSV — alles Nachgelagerte
# (Kontoerkennung über die IBAN, Doppelimport-Erkennung, Zuordnung) gilt
# unverändert weiter.
#
# Zwei Fälle, und sie sind NICHT gleich viel wert:
#
#   1. Aus dem Online-Banking geladen — der Text steckt im PDF. Verlustfrei.
#   2. Papier, abfotografiert oder gescannt — der Text muss erkannt werden.
#      Texterkennung verwechselt bei Zahlen 8/3, 5/6 und 0/8, und über einer
#      Falzkante verliert sie schon mal eine ganze Zeile. Genau das ist an
#      Hans' Beispielauszug passiert (Betrag 1.224,28 lautlos verschwunden).
#
# Deshalb gilt für JEDEN PDF-Import die Saldo-Prüfsumme des Layouts: Anfangs-
# saldo plus alle erkannten Umsätze muss den Endsaldo ergeben, seitenweise.
# Geht sie nicht auf, wird NICHT importiert. Ein Erkennungsfehler bei Geld
# erzeugt keinen Fehler, sondern einen falschen Betrag — und der fällt sonst
# erst auf, wenn eine Abrechnung nicht stimmt.
module Bank
  class PdfImport
    class Error < StandardError; end

    # Reihenfolge = Prüfreihenfolge; ein weiteres Bankformat ist eine Datei
    # plus ein Eintrag hier.
    LAYOUTS = [Bank::Pdf::VrBank].freeze

    TIMEOUT = ENV.fetch("PDFIMPORT_TIMEOUT", "60")
    OCR_TIMEOUT = ENV.fetch("PDFIMPORT_OCR_TIMEOUT", "300")
    # Unter so vielen Zeichen je Seite gehen wir von einem Scan ohne Textschicht
    # aus. Ein leeres Deckblatt hat wenige, ein Auszug hunderte.
    TEXT_SCHWELLE = 120

    # Das extrahierte Zwischenformat ist Text (bbox-XML von pdftotext) und trägt
    # die Spaltenpositionen mit. Es wird anstelle des Rohinhalts durchgereicht —
    # deshalb funktioniert der bestehende Weg über PendingBankStatement (eine
    # Textspalte) unverändert.
    MARKE = "<!-- bank-pdf".freeze

    Ergebnis = Struct.new(:layout, :rows, :konto, :pruefung, :ocr, keyword_init: true) do
      def erkannt? = layout.present?
      def importierbar? = erkannt? && pruefung&.ok?
    end

    def self.pdf?(bytes)
      bytes.to_s.byteslice(0, 5).to_s.start_with?("%PDF")
    end

    # Erkennt das extrahierte Zwischenformat wieder (nach dem Zwischenlagern).
    def self.extrahiert?(text)
      text.to_s.lstrip.start_with?(MARKE)
    end

    # PDF → bbox-XML. Ohne Textschicht wird Texterkennung nachgeschaltet; das
    # Ergebnis ist als solches markiert, damit die Oberfläche es sagen kann.
    def self.extract(bytes, ocr: true)
      Dir.mktmpdir("bankpdf") do |dir|
        pdf = File.join(dir, "auszug.pdf")
        File.binwrite(pdf, bytes)
        xml = pdftotext(pdf, dir)
        erkannt = false
        if ocr && duenn?(xml)
          xml = pdftotext(ocrmypdf(pdf, dir), dir)
          erkannt = true
        end
        "#{MARKE} ocr=#{erkannt} -->\n#{xml}"
      end
    end

    # Prüft, was in einem extrahierten Auszug steht — ohne etwas zu schreiben.
    # Das ist die Antwort auf Hans' Frage, ob der Import gleich nach dem
    # Hochladen sagen kann, ob er das Format kennt.
    def self.analyse(text)
      seiten = Bank::Pdf::TextEbene.parse(text)
      layout = LAYOUTS.find { |l| l.erkennt?(seiten) }
      ocr = text.to_s[/#{Regexp.escape(MARKE)} ocr=(\w+)/, 1] == "true"
      return Ergebnis.new(layout: nil, rows: [], konto: {}, pruefung: nil, ocr: ocr) if layout.nil?

      leser = layout.new(seiten)
      Ergebnis.new(layout: layout, rows: leser.umsaetze, konto: leser.konto,
                   pruefung: leser.pruefung, ocr: ocr)
    end

    def self.parse(text) = analyse(text).rows

    def self.account_info(text)
      a = analyse(text)
      { iban: a.konto[:iban], name: a.konto[:name] }
    end

    def self.duenn?(xml)
      seiten = Bank::Pdf::TextEbene.parse(xml)
      return true if seiten.empty?

      seiten.sum { |s| s.text.length } < TEXT_SCHWELLE * seiten.length
    end

    def self.pdftotext(pfad, dir)
      out = File.join(dir, "#{File.basename(pfad, '.pdf')}.xml")
      ok = system("timeout", TIMEOUT, "pdftotext", "-bbox-layout", pfad, out,
                  out: File::NULL, err: File::NULL)
      raise Error, "pdftotext fehlgeschlagen" unless ok && File.exist?(out)

      File.read(out, encoding: "UTF-8")
    end

    # --force-ocr, weil abfotografierte Auszüge oft eine unbrauchbare
    # Rest-Textschicht mitbringen (Kamera-Apps legen erkannten Text ab).
    #
    # Die drei anderen Schalter sind an Hans' Beispielauszug erarbeitet, nicht
    # geraten: --deskew richtet das schief fotografierte Blatt gerade (sonst
    # driften die Spalten über die Zeile hinweg), --clean entfernt den Schmutz
    # der Falzkante, und --tesseract-pagesegmode 6 („ein zusammenhängender
    # Block") verhindert, dass die senkrechte Beschriftung am Blattrand die
    # automatische Segmentierung zerlegt. Ohne psm 6 verlor die Erkennung
    # reihenweise die Datumsspalte.
    def self.ocrmypdf(pfad, dir)
      out = File.join(dir, "ocr.pdf")
      ok = system("timeout", OCR_TIMEOUT, "ocrmypdf", "--force-ocr", "--language", "deu",
                  "--deskew", "--clean", "--tesseract-pagesegmode", "6",
                  "--output-type", "pdf", pfad, out, out: File::NULL, err: File::NULL)
      raise Error, "Texterkennung fehlgeschlagen (ocrmypdf)" unless ok && File.exist?(out)

      out
    end
  end
end
