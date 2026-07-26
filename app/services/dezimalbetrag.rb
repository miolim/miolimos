# #1171 (aus immoOS #1170 übernommen): DER gemeinsame Parser für
# Betrags-Eingaben — deutsches wie englisches Dezimalformat, ein Regelwerk
# für alle Stellen (GiroCode-Betrag, Rechnungszeilen, Printable-Beträge).
# Vorher existierte das Parsing 3× naiv als `tr(",", ".")`: „1.234,56"
# wurde je nach Stelle still zum Default 0 (BigDecimal-Rescue) oder zu
# 1.234 (to_f) — beim GiroCode ein Zahl-QR-Code über 1,23 € statt 1.234,56 €.
#
# Regeln (nil bei leer/Müll, sonst BigDecimal):
#   "1.234,56" → 1234.56   (Komma = Dezimaltrenner, Punkte = Tausender)
#   "1234.56"  → 1234.56   (ohne Komma: Punkt als Dezimaltrenner …)
#   "1.234"    → 1234      (… AUSSER reine Tausender-Gruppierung: Punkt mit
#   "1.234.567"→ 1234567    genau 3 Nachstellen — im deutschen Kontext ist
#                            das ein Tausenderpunkt, kein Promille-Betrag)
#   "700"      → 700
#   "-12,50"   → -12.5
#   "1.234,56 €" → 1234.56 (Währung/Beiwerk wird abgestreift)
module Dezimalbetrag
  def self.parse(value)
    s = value.to_s.strip.gsub(/[^\d,.\-]/, "")
    return nil if s.blank? || s == "-"
    if s.include?(",")
      s = s.delete(".").tr(",", ".")
    elsif s.match?(/\A-?\d{1,3}(\.\d{3})+\z/)
      s = s.delete(".")
    end
    BigDecimal(s)
  rescue ArgumentError
    nil
  end
end
