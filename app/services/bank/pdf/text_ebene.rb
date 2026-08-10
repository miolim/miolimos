# #1337 Schnitt 3 (aus immoOS #1263): „Kann der Parser erkennen, ob es sich um ein bekanntes
# Format handelt?" — Grundlage dafür ist diese Schicht: Sie macht aus einem PDF
# wieder Zeilen und SPALTEN.
#
# Warum nicht einfach `pdftotext`? Ein Kontoauszug-PDF enthält keine Tabelle,
# sondern einzeln positionierte Zeichen. Die Druckstrecke der VR Bank setzt sie
# so, dass Wortgrenzen im Text NICHT von Zeichenabständen zu unterscheiden sind
# („Olga Schinkewitz" wird zu „O l ga Sch i nk ew i t z"). Wer daraus per
# Textsuche einen Betrag zieht, greift irgendwann daneben — im Verwendungszweck
# `RE1235498810,249128789` steckt die Zeichenfolge `810,24`, die wie ein Betrag
# aussieht und keiner ist.
#
# Deshalb: Die Spalte entscheidet, nicht der Text. Jede Zeile behält ihre
# Zeichen samt x-Position; das Layout fragt gezielt einen x-Bereich ab.
module Bank
  module Pdf
    class TextEbene
      WORT = /<word xMin="([\d.]+)" yMin="([\d.]+)" xMax="([\d.]+)" yMax="([\d.]+)">(.*?)<\/word>/
      SEITE = /<page width="([\d.]+)" height="[\d.]+">(.*?)<\/page>/m

      # Zwei Zeichen gehören zur selben Zeile, wenn ihre Oberkante weniger als
      # das auseinanderliegt (Sub-/Superskript und Rundung abfangen).
      ZEILEN_TOLERANZ = 3.0
      # Ab welcher Lücke im Freitext ein Leerzeichen angenommen wird — relativ
      # zur Zeichenhöhe, damit es bei anderer Schriftgröße mitwandert. Der Wert
      # ist bewusst großzügig: lieber ein Leerzeichen zu wenig als ein Name, der
      # in Silben zerfällt. Für Beträge und Daten spielt er keine Rolle, die
      # kommen aus der Spalte.
      WORT_LUECKE = 0.34

      Zeichen = Struct.new(:x0, :x1, :hoehe, :t)

      Zeile = Struct.new(:y, :zeichen) do
        # Alles in einem x-Bereich, ohne Zwischenräume — so werden aus
        # „9 . 520 , 25" wieder 9.520,25. Für Spalten mit festem Inhalt
        # (Datum, Betrag) ist das der sichere Weg.
        def spalte(von: 0, bis: Float::INFINITY)
          zeichen.select { |z| z.x0 >= von && z.x0 < bis }.map(&:t).join
        end

        # Freitext mit rekonstruierten Wortgrenzen (Name, Verwendungszweck).
        def text(von: 0, bis: Float::INFINITY)
          im_bereich = zeichen.select { |z| z.x0 >= von && z.x0 < bis }
          return "" if im_bereich.empty?

          luecke = im_bereich.map(&:hoehe).max * WORT_LUECKE
          out = +""
          im_bereich.each_with_index do |z, i|
            out << " " if i.positive? && z.x0 - im_bereich[i - 1].x1 > luecke
            out << z.t
          end
          out.strip
        end

        def leer? = zeichen.empty?
        def beginnt_bei = zeichen.first&.x0
      end

      Seite = Struct.new(:nr, :breite, :zeilen) do
        def text = zeilen.map { |z| z.spalte }.join("\n")
      end

      def self.parse(xml) = new(xml).seiten

      def initialize(xml)
        @xml = xml.to_s
      end

      def seiten
        SEITE.match(@xml) ? geteilt : [seite(1, 595.0, @xml)]
      end

      private

      def geteilt
        @xml.scan(SEITE).each_with_index.map { |(breite, inhalt), i| seite(i + 1, breite.to_f, inhalt) }
      end

      def seite(nr, breite, inhalt)
        gruppen = {}
        inhalt.scan(WORT) do |x0, y0, x1, y1, t|
          x0 = x0.to_f
          y0 = y0.to_f
          key = gruppen.keys.find { |k| (k - y0).abs < ZEILEN_TOLERANZ } || y0
          (gruppen[key] ||= []) << Zeichen.new(x0, x1.to_f, y1.to_f - y0, CGI.unescapeHTML(t))
        end
        zeilen = gruppen.sort_by(&:first).map { |y, zs| Zeile.new(y, zs.sort_by(&:x0)) }
        Seite.new(nr, breite, zeilen)
      end
    end
  end
end
