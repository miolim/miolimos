# #1337 Schnitt 3 (aus immoOS #1263): Layout „VR Bank / Atruvia-Druckstrecke" — der Auszug, den
# die Genossenschaftsbanken drucken (Kontokorrent wie Darlehen, gleiches Raster).
#
# Ein Layout beantwortet drei Fragen: Erkenne ich diesen Auszug? Welches Konto
# ist es? Und welche Umsätze stehen drin — mit einer Prüfsumme, die es beweist.
#
# Die Spalten stehen fest im Raster; sie werden über die x-Position gelesen und
# NICHT über Textsuche (Begründung in Bank::Pdf::TextEbene).
module Bank
  module Pdf
    class VrBank
      NAME = "VR Bank (Kontokorrent/Darlehen)".freeze

      # Spaltenraster, gemessen am Auszug bei A4-Breite (595 pt) und dann
      # KALIBRIERT: Ein abfotografierter Auszug ist nie 595 pt breit und selten
      # gerade — feste Punktwerte würden dort die Betragsspalte verfehlen.
      # Fixpunkt ist die H/S-Spalte: Auf jedem VR-Auszug steht rechts neben
      # jedem Betrag ein einzelnes H oder S, und sonst nirgends.
      HS_REFERENZ  = 563.7          # x der H/S-Spalte im ungestreckten Auszug
      # Bu-Tag und Wertstellung stehen direkt hintereinander und ohne
      # verlässliche Lücke — eine Trennlinie dazwischen schnitte mitten in ein
      # Datum („02.01.3" | „1.12."). Beide zusammen lesen, das Muster trennt.
      SP_DATUM_R   = (30.0...125.0)
      SP_TEXT_R    = (125.0...470.0) # Vorgang / Gegenpartei / Verwendungszweck
      SP_BETRAG_R  = (470.0...562.0) # Betrag, rechtsbündig

      DATUM      = /\A(\d{2})\.(\d{2})\.\z/
      DATUM_PAAR = /\A(\d{2}\.\d{2}\.)(\d{2}\.\d{2}\.)\z/
      BETRAG   = /\A(\d{1,3}(?:\.\d{3})*|\d+),(\d{2})\z/
      IBAN     = /\b([A-Z]{2}\d{2}[A-Z0-9]{10,30})\b/
      # Saldozeilen: Anfang, Seitenübertrag, Ende. Ohne Zwischenräume geprüft,
      # weil die Druckstrecke mitten in Wörtern trennt.
      #
      # #1271: Das Datum ist OPTIONAL. Auf dem ersten Auszug eines frisch
      # eröffneten Kontos steht nur „alter Kontostand 0,00" — es gibt keinen
      # Vortag, auf den man sich beziehen könnte. Genau daran scheiterte die
      # Erkennung eines sonst identischen Auszugs.
      ANFANG   = /alterKontostand(?:vom(\d{2}\.\d{2}\.\d{4}))?/
      ENDE     = /neuerKontostand(?:vom(\d{2}\.\d{2}\.\d{4}))?/
      UEBERTRAG_AUF = /Übertragauf(?:Blatt|Seite)/
      UEBERTRAG_VON = /Übertragvon(?:Blatt|Seite)/

      Saldo = Struct.new(:art, :seite, :betrag, :datum, keyword_init: true)

      # Bewusst strukturell statt am Spaltenkopf: Auf einem abfotografierten
      # Auszug erkennt die Texterkennung die Überschrift „Bu-Tag Wert Vorgang"
      # oft gar nicht. Erkannt wird deshalb an der Saldozeile plus einer
      # Betragsspalte mit H/S-Kennung. Falsch-positive fängt die Prüfsumme ab —
      # ein fremdes Layout ergibt niemals einen aufgehenden Saldo.
      def self.erkennt?(seiten)
        seiten = Array(seiten)
        kopf = seiten.first&.text.to_s.gsub(/\s+/, "")
        return false unless kopf.match?(/alterKontostand|Übertragvon(?:Blatt|Seite)/)

        seiten.sum { |s| s.zeilen.count { |z| %w[H S].include?(z.zeichen.last&.t) } } >= 3
      end

      def self.parse(seiten) = new(seiten).umsaetze
      def self.account_info(seiten) = new(seiten).konto
      def self.pruefung(seiten) = new(seiten).pruefung

      def initialize(seiten)
        @seiten = Array(seiten)
        kalibrieren
      end

      # Konto-IBAN/-Bezeichnung aus dem Briefkopf. Die Ziffern stehen dort in
      # Vierergruppen — Leerzeichen raus, dann ist es eine IBAN.
      # Nur der Briefkopf OBERHALB der Tabelle: Im Buchungstext stehen weitere
      # IBANs (Gegenkonten einer Umbuchung), und die dürfen nicht als Konto des
      # Auszugs durchgehen.
      def konto
        kopf = kopfzeilen.map { |z| z.spalte }.join("\n")
        iban = kopf[/IBAN[: ]*([A-Z]{2}[0-9 ]{12,40})/, 1].to_s.gsub(/\s+/, "")
        { iban: iban.presence, name: bezeichnung }
      end

      # Die Kontobezeichnung steht unmittelbar über dem Spaltenkopf
      # („Geschäftskonto Weidestraße 6") — deutlich brauchbarer als der
      # Kontoinhaber, der auf allen Konten derselbe ist.
      # #1271: Die Kontobezeichnung („Geschäftskonto Weidestraße 6") steht
      # RECHTS über dem Spaltenkopf. Links steht die Empfängeranschrift — ohne
      # diese Einschränkung wurde daraus schon mal „23714 Malente".
      def bezeichnung
        kopfzeilen.reverse.each do |z|
          next if z.beginnt_bei.to_f <= @sp_text.first

          t = z.text(von: @sp_text.first).to_s.strip
          # IBAN/BIC, Erstellungsvermerk und Blattzählung sind keine
          # Kontobezeichnung. Bleibt nichts übrig, ist es eben keine da —
          # besser leer als falsch.
          next if t.blank? || t.match?(/IBAN|BIC|erstellt am|Blatt|Nr\.\s*\d/)

          return t
        end
        nil
      end

      def kopfzeilen
        zeilen = @seiten.first&.zeilen.to_a
        i = zeilen.index { |z| z.spalte.gsub(/\s+/, "").start_with?("Bu-Tag") }
        i&.positive? ? zeilen.first(i) : zeilen
      end

      def umsaetze
        @umsaetze ||= lesen[:umsaetze]
      end

      def salden
        @salden ||= lesen[:salden]
      end

      # Die Sicherung, ohne die ich einem eingelesenen PDF nicht trauen würde:
      # Anfangssaldo + alle Umsätze muss den Endsaldo ergeben — und zwar je
      # Seite, damit man eine Abweichung auch findet. Beim Foto eines
      # Papierauszugs ist das der Unterschied zwischen „stimmt" und „sieht
      # plausibel aus".
      Pruefung = Struct.new(:ok, :seiten, :anfang, :ende, :summe, :differenz, keyword_init: true) do
        # #1277 (Hans): „Der Import wird verweigert mit ,Abweichung 0,00 €`."
        #
        # Maßgeblich ist die GESAMTdifferenz: Anfangssaldo + alle gelesenen
        # Umsätze = Endsaldo. Geht die auf, ist kein Umsatz verlorengegangen —
        # dann darf importiert werden.
        #
        # Eine einzelne SEITE kann trotzdem nicht aufgehen: Wird ein
        # Seitenübertrag falsch gelesen, verschiebt sich ein Betrag zwischen
        # zwei Seiten, ohne dass in der Summe etwas fehlt. Das ist ein Hinweis
        # auf die Lesequalität, kein Grund, den Import zu verweigern — vorher
        # blockierte es ihn, und die Meldung nannte dabei die (null-)Gesamt-
        # differenz. Das musste unverständlich wirken.
        def ok? = ok
        def seiten_ok? = seiten.all? { |s| s[:ok] }
        def fehlerhafte_seiten = seiten.reject { |s| s[:ok] }.map { |s| s[:seite] }
      end

      def pruefung
        pro_seite = @seiten.map { |s| seitenpruefung(s.nr) }.compact
        anfang = salden.find { |s| s.art == :anfang }
        ende   = salden.find { |s| s.art == :ende }
        return Pruefung.new(ok: false, seiten: pro_seite, anfang: nil, ende: nil,
                            summe: nil, differenz: nil) if anfang.nil? || ende.nil?

        summe = umsaetze.sum { |u| u[:amount] }
        diff  = (anfang.betrag + summe - ende.betrag).round(2)
        Pruefung.new(ok: diff.zero?, seiten: pro_seite,
                     anfang: anfang.betrag, ende: ende.betrag, summe: summe, differenz: diff)
      end

      private

      # Die H/S-Zeichen ganz rechts verraten, wie das Raster auf DIESEM Auszug
      # sitzt. Median statt Mittelwert: Ein schief fotografiertes Blatt hat
      # Ausreißer, und die dürfen das Raster nicht verziehen.
      def kalibrieren
        kandidaten = @seiten.flat_map do |s|
          s.zeilen.filter_map do |z|
            letztes = z.zeichen.last
            letztes&.x0 if %w[H S].include?(letztes&.t) && letztes.x0 > s.breite * 0.75
          end
        end
        hs = kandidaten.sort[kandidaten.length / 2] if kandidaten.length >= 3
        versatz = hs ? hs - HS_REFERENZ : 0.0
        @sp_datum   = verschoben(SP_DATUM_R, versatz)
        @sp_text    = verschoben(SP_TEXT_R, versatz)
        @sp_betrag  = verschoben(SP_BETRAG_R, versatz)
        @sp_hs      = ((hs || HS_REFERENZ) - 4.0...Float::INFINITY)
      end

      def verschoben(bereich, versatz)
        (bereich.first + versatz...bereich.last + versatz)
      end

      def seitenpruefung(nr)
        start = salden.find { |s| s.seite == nr && %i[anfang uebertrag_von].include?(s.art) }
        schluss = salden.find { |s| s.seite == nr && %i[ende uebertrag_auf].include?(s.art) }
        return nil if start.nil? || schluss.nil?

        summe = umsaetze.select { |u| u[:seite] == nr }.sum { |u| u[:amount] }
        diff = (start.betrag + summe - schluss.betrag).round(2)
        { seite: nr, ok: diff.zero?, differenz: diff, summe: summe }
      end

      def lesen
        @lesen ||= begin
          umsaetze = []
          salden = []
          @seiten.each do |seite|
            seite.zeilen.each do |zeile|
              betrag = betrag_von(zeile)
              if (s = saldo_von(zeile, seite.nr, betrag))
                salden << s
              elsif (u = buchung_von(zeile, seite.nr, betrag))
                umsaetze << u
              elsif umsaetze.any? && betrag.nil?
                anhaengen(umsaetze.last, zeile)
              end
            end
          end
          jahre_setzen(umsaetze, salden)
          { umsaetze: umsaetze.map { |u| fertig(u) }, salden: salden }
        end
      end

      # Betrag NUR aus der Betragsspalte — im Verwendungszweck stehen Ziffern-
      # folgen, die wie Beträge aussehen (`RE1235498810,249128789`).
      def betrag_von(zeile)
        roh = zeile.spalte(von: @sp_betrag.first, bis: @sp_betrag.last)
        return nil unless (m = BETRAG.match(roh))

        hs = zeile.spalte(von: @sp_hs.first).strip
        return nil unless %w[H S].include?(hs)

        wert = BigDecimal("#{m[1].delete('.')}.#{m[2]}")
        hs == "H" ? wert : -wert
      end

      def saldo_von(zeile, nr, betrag)
        return nil if betrag.nil?

        text = zeile.spalte(von: @sp_text.first, bis: @sp_betrag.last).gsub(/\s+/, "")
        if (m = ANFANG.match(text))
          Saldo.new(art: :anfang, seite: nr, betrag: betrag, datum: datum(m[1]))
        elsif (m = ENDE.match(text))
          Saldo.new(art: :ende, seite: nr, betrag: betrag, datum: datum(m[1]))
        elsif text.match?(UEBERTRAG_AUF)
          Saldo.new(art: :uebertrag_auf, seite: nr, betrag: betrag)
        elsif text.match?(UEBERTRAG_VON)
          Saldo.new(art: :uebertrag_von, seite: nr, betrag: betrag)
        end
      end

      def buchung_von(zeile, nr, betrag)
        return nil if betrag.nil?

        paar = DATUM_PAAR.match(zeile.spalte(von: @sp_datum.first, bis: @sp_datum.last).strip)
        return nil if paar.nil?

        { seite: nr, bu: paar[1], wert: paar[2], amount: betrag,
          art: zeile.text(von: @sp_text.first, bis: @sp_text.last),
          zeilen: [] }
      end

      def anhaengen(umsatz, zeile)
        t = zeile.text(von: @sp_text.first, bis: @sp_text.last)
        umsatz[:zeilen] << t if t.present?
      end

      # Die Falle des Jahresauszugs: Buchungstage tragen NUR Tag und Monat. Das
      # Jahr steht einmal im Anfangssaldo („alter Kontostand vom 30.12.2024") —
      # und springt, sobald der Monat kleiner wird als beim Umsatz davor. Ohne
      # das landet der komplette Januar im Vorjahr.
      def jahre_setzen(umsaetze, salden)
        anfang = salden.find { |s| s.art == :anfang }&.datum
        ende = salden.find { |s| s.art == :ende }&.datum
        return vorwaerts(umsaetze, anfang) if anfang
        return rueckwaerts(umsaetze, ende) if ende

        umsaetze.each { |u| u[:jahr] = Date.current.year }
      end

      # Der Normalfall: Das Jahr steht im Anfangssaldo und springt, sobald der
      # Monat kleiner wird als beim Umsatz davor (Dezember-Saldo → Januar).
      def vorwaerts(umsaetze, anfang)
        jahr = anfang.year
        vormonat = anfang.month
        umsaetze.each do |u|
          monat = u[:bu][3, 2].to_i
          jahr += 1 if monat < vormonat
          vormonat = monat
          u[:jahr] = jahr
        end
      end

      # #1271: Ohne Anfangsdatum (erster Auszug eines neuen Kontos) bleibt nur
      # der Endsaldo — dann von hinten rechnen: Der letzte Umsatz liegt im
      # Endmonat; wird der Monat rückwärts GRÖSSER, war es das Vorjahr.
      def rueckwaerts(umsaetze, ende)
        jahr = ende.year
        folgemonat = ende.month
        umsaetze.reverse_each do |u|
          monat = u[:bu][3, 2].to_i
          jahr -= 1 if monat > folgemonat
          folgemonat = monat
          u[:jahr] = jahr
        end
      end

      NUR_DATUM = /\A\d{2}\.\d{2}\.\d{2,4}\z/

      def fertig(u)
        # #1271: Bei Abschluss-/Entgeltbuchungen gibt es keinen Zahler; in der
        # Folgezeile steht dann das Abschlussdatum. Als „Gegenpartei" wäre das
        # irreführend — und landete beim Verknüpfen als Kontaktname im Bestand.
        gegenpartei = u[:zeilen].first
        gegenpartei = nil if gegenpartei.to_s.strip.match?(NUR_DATUM)
        zweck = u[:zeilen].drop(1).join(" ").squeeze(" ").strip
        zweck = "" unless zweck.match?(/[[:alnum:]]/)
        # #1337: je Zeile suchen statt im zusammengeklebten Block. Im Fork
        # wurden alle Folgezeilen erst verbunden und dann die Leerzeichen
        # entfernt — eine IBAN direkt hinter einem Wort („…AbschlagStromDE02…")
        # hat danach keine Wortgrenze mehr und wurde nicht gefunden. Zeilenweise
        # kann nichts zusammenwachsen, was nicht zusammengehört.
        iban = u[:zeilen].filter_map { |z| z.gsub(/\s+/, "")[IBAN, 1] }.first
        gebucht = tag(u[:bu], u[:jahr])
        { booked_on: gebucht,
          value_date: wertstellung(u, gebucht) || gebucht,
          amount: u[:amount], currency: "EUR",
          purpose: [u[:art], zweck].reject(&:blank?).join(" · ").presence,
          counterparty_name: gegenpartei.presence,
          counterparty_iban: iban,
          bank_ref: nil, seite: u[:seite] }
      end

      # Die Wertstellung liegt nicht zwingend im selben Jahr wie die Buchung:
      # Am 02.01. gebucht, zum 31.12. wertgestellt — das ist der Dezember DAVOR.
      # Ohne diese Korrektur wandert der Umsatz um ein Jahr.
      def wertstellung(u, gebucht)
        return nil if gebucht.nil?

        monat = u[:wert][3, 2].to_i
        jahr = u[:jahr]
        jahr -= 1 if monat - gebucht.month > 6
        jahr += 1 if gebucht.month - monat > 6
        tag(u[:wert], jahr)
      end

      # Bankauszüge kennen den 30.02. — eine Wertstellungskonvention, kein
      # Kalendertag. #1337: die Klemmung ans Monatsende steht zentral in
      # Bank::Datum, damit sie für alle drei Importwege gleich gilt.
      def tag(tm, jahr) = Bank::Datum.im_monat(tm, jahr)

      # #1271: Das Datum kann fehlen (erster Auszug eines neuen Kontos).
      def datum(s) = Bank::Datum.parse(s)
    end
  end
end
