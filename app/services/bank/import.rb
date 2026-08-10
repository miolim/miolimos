# #1337 Schnitt 3 (aus immoOS #975/#1014/#1263): Bankimport-Orchestrierung. Erkennt CAMT (XML) vs.
# CSV, parst zu normalisierten Umsätzen und legt sie am Konto an — mit
# Doppelimport-Erkennung über einen Fingerprint je Umsatz. Doppelt vorhandene
# Umsätze (auch bei überlappenden Auszügen) werden übersprungen, nicht dupliziert.
module Bank
  class Import
    require "digest"

    # #1014 (Hans): imported_ids = die tatsächlich neu angelegten Umsätze
    # dieses Auszugs → in der Umsatzliste als „neu" markieren. #1014 (B):
    # statement = der angelegte Kontoauszug-Datensatz (nil, wenn nichts Neues).
    Result = Struct.new(:imported, :skipped, :format, :imported_ids, :statement,
                        :pruefung, :layout, keyword_init: true)

    # #996 (Hans): Ergebnis der Konto-Erkennung eines Uploads — Format, die im
    # Auszug hinterlegte Konto-IBAN/-Inhaber, Anzahl Buchungen und das passende
    # HV-Konto (nil = nicht erkannt → manuelle Zuordnung).
    # #1263: pruefung/ocr/layout sind bei PDF gefüllt — die Oberfläche sagt
    # damit direkt nach dem Hochladen, ob das Format bekannt ist und ob die
    # gelesenen Umsätze zum Saldo passen. Bei CAMT/CSV bleiben sie leer; dort
    # ist der Inhalt maschinenlesbar und braucht keinen Beweis.
    Detection = Struct.new(:format, :account_iban, :account_name, :entry_count, :ledger,
                           :pruefung, :ocr, :layout, keyword_init: true) do
      def pdf? = format == :pdf
      # Bei PDF wird nur importiert, wenn die Prüfsumme aufgeht (siehe
      # Bank::PdfImport). Alles andere ist wie bisher importierbar.
      def sicher? = !pdf? || pruefung&.ok?
    end

    def self.call(ledger, content, filename: nil, source_path: nil, trotz_abweichung: false,
                  rows: nil, korrigiert: false)
      new(ledger, content, filename: filename, source_path: source_path,
          trotz_abweichung: trotz_abweichung, rows: rows, korrigiert: korrigiert).call
    end

    # #996: erkennt anhand der im Kontoauszug hinterlegten Konto-IBAN, zu welchem
    # HV-Konto (BankLedger) der Upload gehört. CAMT trägt die IBAN strukturiert
    # (Stmt/Rpt → Acct), CSV bestenfalls in der Präambel (best effort).
    def self.detect(content)
      content = content.to_s
      return detect_pdf(content) if PdfImport.extrahiert?(content)

      camt = camt_content?(content)
      info = camt ? CamtImport.account_info(content) : csv_account_info(content)
      iban = normalize_iban(info[:iban])
      rows = camt ? CamtImport.parse(content) : CsvImport.parse(content)
      ledger = iban.present? ? BankLedger.find_by(iban: iban) : nil
      Detection.new(format: camt ? :camt : :csv, account_iban: iban,
                    account_name: info[:name].presence, entry_count: rows.length, ledger: ledger)
    end

    # #1263 (Hans): „Kann der Parser erkennen, ob es sich um ein bekanntes
    # Format handelt?" — hier ist die Antwort. Ein PDF wird einmal analysiert;
    # Layout, Konto, Umsatzzahl und Prüfsumme stehen danach fest, ohne dass
    # etwas geschrieben wurde.
    def self.detect_pdf(content)
      a = PdfImport.analyse(content)
      iban = normalize_iban(a.konto[:iban])
      Detection.new(format: :pdf, account_iban: iban, account_name: a.konto[:name].presence,
                    entry_count: a.rows.length,
                    ledger: iban.present? ? BankLedger.find_by(iban: iban) : nil,
                    pruefung: a.pruefung, ocr: a.ocr,
                    layout: a.erkannt? ? a.layout.const_get(:NAME) : nil)
    end

    def self.camt_content?(content)
      s = content.to_s.lstrip
      s.start_with?("<") && s.include?("<Ntry")
    end

    def self.normalize_iban(raw)
      raw.to_s.gsub(/\s+/, "").upcase.presence
    end

    # CSV-Präambel (Zeilen vor der Datentabelle) nach einer IBAN durchsuchen.
    def self.csv_account_info(content)
      head = content.to_s.split(/\r\n|\r|\n/).first(15).join("\n")
      m = head.match(/\b([A-Z]{2}\d{2}(?:\s?[A-Z0-9]){10,30})\b/)
      { iban: m && m[1], name: nil }
    end

    def initialize(ledger, content, filename: nil, source_path: nil, trotz_abweichung: false,
                   rows: nil, korrigiert: false)
      @ledger   = ledger
      @content  = content.to_s
      @filename = filename
      # #1275: Pfad der aufbewahrten Originaldatei (PDF) — der Auszug IST bei
      # einem PDF-Import der Beleg; ohne ihn bleibt nur das Gelesene.
      @source_path = source_path
      # #1277 (Hans): ausdrücklich gewollter Import trotz nicht aufgehendem
      # Saldo. Der Standard bleibt: ohne Prüfsumme kein Import.
      @trotz_abweichung = trotz_abweichung
      # #1277: in der Vorschau korrigierte Zeilen. Liegen sie vor, gelten SIE —
      # das Gelesene war ja gerade der Fehler.
      @rows = rows
      @korrigiert = korrigiert
    end

    def call
      return import_pdf if pdf?

      rows = camt? ? CamtImport.parse(@content) : CsvImport.parse(@content)
      insert(rows, camt? ? :camt : :csv)
    end

    private

    # Bei PDF ist der Import an die Prüfsumme gebunden: Geht sie nicht auf,
    # wird NICHT geschrieben. Ein falsch gelesener Betrag erzeugt keinen
    # Fehler, sondern eine stille Abweichung — die fällt sonst erst auf, wenn
    # eine Abrechnung nicht stimmt.
    def import_pdf
      a = PdfImport.analyse(@content)
      return insert_korrigiert if @rows.present?

      unless a.importierbar? || (@trotz_abweichung && a.erkannt?)
        return Result.new(imported: 0, skipped: 0, format: :pdf, imported_ids: [],
                          statement: nil, pruefung: a.pruefung,
                          layout: a.erkannt? ? a.layout.const_get(:NAME) : nil)
      end

      insert(a.rows, :pdf).tap do |r|
        r.pruefung = a.pruefung
        # Der Auszug trägt den Vermerk, dass sein Saldo nicht aufging — sonst
        # sieht ein bewusst erzwungener Import später aus wie ein geprüfter.
        if r.statement && !a.pruefung&.ok?
          r.statement.update_columns(
            note: I18n.t("bank.import.pdf_unchecked_note",
                         diff: ActiveSupport::NumberHelper.number_to_currency(
                           a.pruefung&.differenz || 0, unit: "€", format: "%n %u", locale: :de)),
            updated_at: Time.current
          )
        end
      end
    end

    # #1277: Import aus den korrigierten Zeilen. Am Auszug bleibt vermerkt, dass
    # beim Einlesen korrigiert wurde — nicht als Makel, sondern damit später
    # niemand rätselt, warum die Zahlen vom Rohtext abweichen.
    def insert_korrigiert
      insert(@rows, :pdf).tap do |r|
        next unless r.statement && @korrigiert

        r.statement.update_columns(note: I18n.t("bank.import.pdf_corrected_note"),
                                   updated_at: Time.current)
      end
    end

    def pdf?
      return @pdf unless @pdf.nil?
      @pdf = PdfImport.extrahiert?(@content)
    end

    def camt?
      return @camt unless @camt.nil?
      @camt = self.class.camt_content?(@content)
    end

    def insert(rows, fmt)
      imported = 0
      skipped  = 0
      imported_ids = []
      seen = Hash.new(0) # base-Fingerprint → Vorkommen innerhalb dieses Imports

      booked = []
      rows.each do |r|
        fp = fingerprint(r, seen)
        rec = @ledger.bank_transactions.build(
          booked_on: r[:booked_on], value_date: r[:value_date], amount: r[:amount],
          currency: r[:currency].presence || "EUR", purpose: r[:purpose],
          counterparty_name: r[:counterparty_name],
          counterparty_iban: r[:counterparty_iban].to_s.gsub(/\s+/, "").upcase.presence,
          bank_ref: r[:bank_ref], fingerprint: fp, source: fmt
        )
        begin
          if rec.save
            imported += 1
            imported_ids << rec.id
            booked << rec.booked_on
          else
            skipped += 1 # Fingerprint bereits vorhanden = Doppelimport
          end
        rescue ActiveRecord::RecordNotUnique
          skipped += 1
        end
      end

      # #1014 (B): den Auszug als Entität festhalten und die neu angelegten
      # Umsätze ihm zuordnen. Nur wenn tatsächlich etwas Neues kam (ein reiner
      # Doppelimport erzeugt keinen leeren Auszug).
      statement = nil
      if imported_ids.any?
        dates = booked.compact
        statement = @ledger.bank_statements.create!(
          filename: @filename, format: fmt.to_s, source_path: @source_path,
          entry_count: imported, skipped_count: skipped,
          period_from: dates.min, period_to: dates.max)
        @ledger.bank_transactions.where(id: imported_ids).update_all(bank_statement_id: statement.id)
      end

      Result.new(imported: imported, skipped: skipped, format: fmt,
                 imported_ids: imported_ids, statement: statement)
    end

    # Eindeutige Bank-Referenz bevorzugen; sonst Hash der Kernfelder + laufende
    # Nummer bei mehreren identischen Umsätzen innerhalb desselben Auszugs (so
    # dass ein erneuter Import derselben Datei deterministisch dieselben
    # Fingerprints erzeugt → alle als Duplikat erkannt).
    def fingerprint(r, seen)
      if r[:bank_ref].present?
        "ref:#{r[:bank_ref]}"
      else
        base = Digest::SHA256.hexdigest(
          [@ledger.id, r[:booked_on], r[:amount].to_s, r[:purpose],
           r[:counterparty_iban], r[:counterparty_name]].join("|")
        )
        seen[base] += 1
        "#{base}##{seen[base]}"
      end
    end
  end
end
