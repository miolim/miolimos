# #1337 Schnitt 3: Datumslesung für Kontoauszüge — an EINER Stelle, validiert.
#
# immoos_builder aus dem Fork-Betrieb: „Datumsfallen. Dreimal aufgetreten,
# darunter ein 30.02. aus der Erkennung. Jedes gelesene Datum gehört validiert,
# nicht geparst und geglaubt."
#
# Das ist nicht Pedanterie. `Date.parse("30.02.2026")` wirft — ein Import, der
# das nicht abfängt, verliert die Zeile oder stirbt mitten im Auszug. Und
# `Date.parse` ist großzügig genug, aus Unsinn ein Datum zu machen, das dann
# jahrelang im Bestand steht.
#
# Zwei getrennte Wege, weil zwei verschiedene Dinge gemeint sind:
#
#   `parse`  — ein vollständiges Datum aus Text. Ungültiges ist nil, nie ein
#              geratenes Datum.
#   `im_monat` — Tag und Monat aus einem Auszug, dessen Jahr von außen kommt.
#              Bankauszüge kennen den 30.02.: eine Wertstellungskonvention, kein
#              Kalendertag. Der Tag wird deshalb ans Monatsende geklemmt, statt
#              den Umsatz zu verlieren.
module Bank
  module Datum
    DEUTSCH = /\A(\d{1,2})[.](\d{1,2})[.](\d{2,4})\z/
    ISO     = /\A(\d{4})-(\d{2})-(\d{2})\z/

    module_function

    def parse(raw)
      s = raw.to_s.strip
      return nil if s.blank?

      if (m = DEUTSCH.match(s))
        jahr = m[3].length == 2 ? "20#{m[3]}".to_i : m[3].to_i
        bauen(jahr, m[2].to_i, m[1].to_i)
      elsif (m = ISO.match(s))
        bauen(m[1].to_i, m[2].to_i, m[3].to_i)
      else
        # Letzter Ausweg für Formate, die wir nicht kennen (CAMT liefert ISO
        # mit Zeitanteil). Ein Fehlschlag ist nil, keine Ausnahme.
        Date.parse(s)
      end
    rescue ArgumentError, TypeError, Date::Error
      nil
    end

    # Tag/Monat („02.01.") mit einem von außen bestimmten Jahr. Der Tag wird
    # ans Monatsende geklemmt — der 30.02. eines Auszugs ist der Monatsletzte,
    # kein Grund, die Zeile fallenzulassen.
    def im_monat(tag_monat, jahr)
      m = /\A(\d{1,2})\.(\d{1,2})\.?\z/.match(tag_monat.to_s.strip) or return nil
      monat = m[2].to_i
      return nil unless monat.between?(1, 12)
      return nil unless jahr.to_i.between?(1900, 2999)

      letzter = Date.new(jahr.to_i, monat, -1).day
      Date.new(jahr.to_i, monat, [m[1].to_i, letzter].min)
    rescue Date::Error
      nil
    end

    def bauen(jahr, monat, tag)
      return nil unless jahr.between?(1900, 2999) && monat.between?(1, 12) && tag.between?(1, 31)
      Date.new(jahr, monat, tag)
    rescue Date::Error
      nil
    end
  end
end
