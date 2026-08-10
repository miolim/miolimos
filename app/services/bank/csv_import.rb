# #1337 Schnitt 3 (aus immoOS #975): generischer CSV-Parser für Bankumsätze. Erkennt das
# Trennzeichen (; oder ,), ordnet die Spalten fuzzy per Kopfzeile zu (deutsche
# Bank-Exporte) und liest den Betrag im deutschen Format (1.234,56; − = Aus-
# zahlung). Eigener kleiner CSV-Reader (RFC-4180, quotes) — bewusst ohne das
# csv-Gem (in Ruby 3.4 kein Default-Gem; der Rollout macht kein bundle install).
module Bank
  class CsvImport
    HEADERS = {
      booked_on:         /buchung|buchungstag|datum|valuta|booking/i,
      value_date:        /wert|valuta/i,
      amount:            /betrag|umsatz|amount|soll.?haben/i,
      purpose:           /verwendung|zweck|buchungstext|vwz|purpose|text/i,
      counterparty_name: /name|beguenstigt|empf|auftraggeber|zahlungspflicht|beteiligt/i,
      counterparty_iban: /iban|kontonummer/i
    }.freeze

    def self.parse(content)
      content = content.encode("UTF-8", invalid: :replace, undef: :replace) unless content.valid_encoding?
      delim = content.count(";") >= content.count(",") ? ";" : ","
      rows = read_rows(content, delim)
      return [] if rows.length < 2

      header = rows.first
      cols = map_columns(header)
      return [] if cols[:amount].nil?

      rows[1..].filter_map { |cells| row_to_tx(cells, header, cols) }
    end

    # Kopfzeile finden (Präambeln überspringen): erste Zeile, die ≥ 2 bekannte
    # Spaltennamen trifft; ab dort parsen.
    def self.read_rows(content, delim)
      lines = content.split(/\r\n|\r|\n/).reject(&:blank?)
      start = lines.index do |ln|
        HEADERS.values.count { |re| ln =~ re } >= 2
      end || 0
      lines[start..].map { |ln| split_line(ln, delim) }
    end

    # RFC-4180-ähnlich: Felder durch delim getrennt, optional in "…" gequotet,
    # "" = escaptes Anführungszeichen.
    def self.split_line(line, delim)
      fields = []
      field = +""
      in_q = false
      i = 0
      while i < line.length
        c = line[i]
        if in_q
          if c == '"'
            if line[i + 1] == '"' then field << '"'; i += 1 else in_q = false end
          else
            field << c
          end
        elsif c == '"'
          in_q = true
        elsif c == delim
          fields << field; field = +""
        else
          field << c
        end
        i += 1
      end
      fields << field
      fields.map(&:strip)
    end

    def self.map_columns(header)
      HEADERS.transform_values do |re|
        header.index { |h| h.to_s =~ re }
      end
    end

    def self.row_to_tx(cells, header, cols)
      at = ->(k) { i = cols[k]; i && cells[i] }
      amount = parse_amount(at.(:amount))
      return nil if amount.nil?
      {
        amount: amount,
        currency: "EUR",
        booked_on: parse_date(at.(:booked_on)),
        value_date: parse_date(at.(:value_date) || at.(:booked_on)),
        purpose: at.(:purpose).to_s.squish.presence,
        counterparty_name: at.(:counterparty_name).to_s.squish.presence,
        counterparty_iban: at.(:counterparty_iban).to_s.gsub(/\s+/, "").upcase.presence,
        bank_ref: nil
      }
    end

    # #1170 (R1): zentral in Dezimalbetrag — hier nur noch der Delegat.
    def self.parse_amount(str)
      Dezimalbetrag.parse(str)
    end

    # #1337: zentral in Bank::Datum — validiert, nie geraten.
    def self.parse_date(str) = Bank::Datum.parse(str)
  end
end
