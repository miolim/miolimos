# #1677 (aus immoOS #1658 R6 übernommen; Hans dort): „Können wir dasselbe auch
# für andere Interface-Elemente ergänzen, also insbesondere Feldbezeichnungen
# und Abschnittsbezeichnungen?"
#
# Bei den Icons musste ein Verzeichnis her (UiElemente). Hier gibt es längst
# eines: die Übersetzungsdateien. Ein Hilfetext zitiert den SCHLÜSSEL einer
# Beschriftung —
#
#   :feld:tasks.fields.due_date:        → **Fällig**
#   :bereich:knowledge.editors.relationships.title:   → ***Beziehungen***
#
# — und zeigt damit immer den Text, den das Programm gerade benutzt, in der
# Sprache dessen, der liest.
#
# Diese Klasse ist das Nachschlagewerk in beide Richtungen: Schlüssel → Text
# (fürs Rendern) und Text → Schlüssel (für den Beschriftungs-Modus und die
# Suche am Schreibfeld).
class I18nBeschriftungen
  # Im Fork stand hier fest `:de`. Upstream ist zweisprachig mit erzwungener
  # Parität (#619) — gelesen wird in der Sprache des Aufrufs, mit der
  # Vorgabesprache als Rückfall für einen Schlüssel, den es dort (noch) nicht gibt.
  def self.sprachen = [I18n.locale, I18n.default_locale].uniq

  # Was als Beschriftung taugt: kurz, ohne Platzhalter, ohne Zeilenumbruch.
  # Ein ganzer Hinweissatz ist keine Feldbezeichnung.
  MAX_LAENGE = 60

  class << self
    # { "real_estate.properties.total_living" => "Wohnungsfläche gesamt", … }
    def alle(sprache = I18n.locale)
      @alle ||= {}
      @alle[sprache.to_sym] ||= begin
        # Die Übersetzungen werden faul geladen — ohne diesen Anstoß ist die
        # Tabelle beim ersten Zugriff leer (und das Nachschlagen still wirkungslos).
        I18n.backend.load_translations
        flach = {}
        sprachen_fuer(sprache).reverse_each do |s|
          sammeln(I18n.backend.send(:translations)[s.to_sym] || {}, "", flach)
        end
        flach
      end
    end

    # Die gefragte Sprache zuletzt — sie überschreibt den Rückfall.
    def sprachen_fuer(sprache) = [sprache.to_sym, I18n.default_locale].uniq

    def text(schluessel) = alle[schluessel.to_s]

    def kennt?(schluessel) = alle.key?(schluessel.to_s)

    # Volltextsuche für die Auswahl am Schreibfeld — gesucht wird nach dem, was
    # auf dem Bildschirm steht, nicht nach dem Schlüssel.
    # `bereich` ist die Karten-Art, zu der geschrieben wird (property, unit …).
    # Ohne sie griff Hans beim ersten Gebrauch daneben: Die Suche nach
    # „Bezeichnung" bot den Platzhalter des BANK-Editors an, und der sieht in
    # der Liste genauso richtig aus wie das Feld der Grundstücks-Card. Treffer
    # aus dem passenden Zusammenhang stehen deshalb oben.
    def suche(begriff, grenze: 30, bereich: nil)
      such = begriff.to_s.strip.downcase
      return [] if such.length < 2

      stamm = stamm_von(bereich)
      treffer = alle.select { |schluessel, wert| wert.downcase.include?(such) || schluessel.include?(such) }
      treffer.sort_by do |schluessel, wert|
        [stamm && schluessel.include?(stamm) ? 0 : 1,   # zur Karte passend
         wert.downcase.start_with?(such) ? 0 : 1,       # beginnt mit dem Begriff
         wert.length, schluessel]
      end.first(grenze)
    end

    # Rückwärts: Zu genau diesem sichtbaren Text die Schlüssel finden.
    #
    # `bereich` ist der Zusammenhang des Klicks (die Karten-Art, z. B.
    # "property"). „Wohnungsfläche gesamt" gibt es am Grundstück UND am
    # Gebäude — beide zeigen denselben Text, und wer den falschen zitiert,
    # folgt später der falschen Umbenennung. Deshalb gewinnt der Schlüssel,
    # der zur Karte passt, auf der geklickt wurde.
    def zu_text(sichtbarer_text, bereich: nil)
      text = sichtbarer_text.to_s.strip
      return [] if text.empty? || text.length > MAX_LAENGE

      treffer = alle.select { |_, wert| wert == text }.keys
      return treffer if treffer.size < 2 || bereich.blank?

      stamm = stamm_von(bereich) or return treffer
      passend, rest = treffer.partition { |schluessel| schluessel.include?(stamm) }
      passend + rest
    end

    def zuruecksetzen! = @alle = nil

    # Die Karten-Art als Wortstamm, wie er in den Übersetzungsschlüsseln
    # vorkommt: „list:tasks" → „task", „ki.master_data" → „knowledge". Treffer
    # aus dem passenden Zusammenhang stehen damit oben. (Im Fork: `property` →
    # `propert` per abgeschnittenem „y".)
    STAEMME = { "ki" => "knowledge", "inboxitem" => "inbox", "timeentry" => "time_entr",
                "bankledger" => "bank", "persons" => "person" }.freeze

    def stamm_von(bereich)
      art = bereich.to_s.downcase.delete_prefix("list:").split(".").first.to_s
      return nil if art.empty?

      STAEMME[art] || art.delete_suffix("s").delete_suffix("y").presence
    end

    # Nur für Tests: tut so, als hieße jede Beschriftung anders — so lässt sich
    # prüfen, dass der Hilfetext der Umbenennung folgt.
    def stub_text(ersatz)
      original = method(:text)
      define_singleton_method(:text) { |_schluessel| ersatz }
      yield
    ensure
      define_singleton_method(:text, original)
    end

    private

    def sammeln(knoten, praefix, ziel)
      knoten.each do |schluessel, wert|
        pfad = praefix.empty? ? schluessel.to_s : "#{praefix}.#{schluessel}"
        case wert
        when Hash then sammeln(wert, pfad, ziel)
        when String
          next if wert.length > MAX_LAENGE || wert.include?("%{") || wert.include?("\n")

          ziel[pfad] = wert
        end
      end
    end
  end
end
