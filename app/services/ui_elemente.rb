# #1669 (Übergabe aus immoOS #1664/#1658): Das Verzeichnis der Bedienelemente.
#
# Ein Knopf, der nur ein Symbol trägt, hat keinen Namen. Weder ein Mensch noch
# ein Hilfetext noch eine geführte Tour kann auf ihn zeigen: Auf einer Card
# stehen leicht ein Dutzend identische Plus-Symbole, und ein Zeiger auf den
# Bild-Namen (`:icon:plus_circle:`) trifft davon das erste im Markup.
#
# Ein Eintrag hier ist die EINE Quelle für „welches Symbol trägt dieser Befehl
# und wie heißt er":
#
#   Im Programm:   <%= ui_button :ki_anlegen, ... %>
#   Später:        Befehls-Suche und geführte Touren hängen am selben Anker.
#
# Eine Kennung je BEFEHL, nicht je Symbol: „Kontaktweg hinzufügen" und
# „Kennung hinzufügen" sind zwei Einträge, obwohl beide ein Plus zeigen.
#
# Hans' Frage in #1664 war die bessere Idee: „Könnte die Registrierung im
# Katalog nicht technische Voraussetzung für das Einfügen eines Buttons sein?"
# — Ja. Der Helfer `ui_button` ist diese Voraussetzung.
module UiElemente
  class Unbekannt < StandardError; end

  # ALLE `config/ui_elemente*.yml` — nicht nur die Basis.
  #
  # miolimOS schreibt seine Einträge in `ui_elemente.yml`. Ein Fork (immoOS)
  # legt `ui_elemente.immoos.yml` daneben und wird allein dadurch gelesen; er
  # muss diese Datei nicht anfassen. Das ist der Unterschied zur immoOS-Fassung,
  # die zwei Pfade fest aufzählt: So bleibt nach einem Release-Merge NICHTS vom
  # Katalog-Mechanismus im Fork liegen, nur seine eigene YAML-Datei.
  def self.dateien = Dir.glob(Rails.root.join("config/ui_elemente*.yml")).sort

  # Schlüssel, die in einem Text vorkommen dürfen — eng gefasst, damit eine
  # Kennung nie zu einem Dateipfad werden kann.
  SCHLUESSEL_RE = /\A[a-z0-9_]{1,60}\z/

  class << self
    # schluessel => { icon: Dateiname in app/views/shared/icons, label: i18n-Key }
    def elemente
      @elemente ||= laden
    end

    def [](schluessel) = elemente[schluessel.to_s]

    def kennt?(schluessel) = elemente.key?(schluessel.to_s)

    def icon_fuer(schluessel) = elemente.dig(schluessel.to_s, :icon)

    def label_fuer(schluessel) = elemente.dig(schluessel.to_s, :label)

    # Für Tests und den Entwicklungs-Neustart: Dateien erneut lesen.
    def neu_laden! = (@elemente = laden)

    private

    def laden
      dateien.each_with_object({}) do |datei, alle|
        (YAML.safe_load_file(datei) || {}).each do |schluessel, eintrag|
          # Eine Kennung zweimal wäre ein stiller Streit zwischen Basis und
          # Fork — lieber laut beim Start als lautlos in der Oberfläche.
          if alle.key?(schluessel.to_s)
            raise Unbekannt, "Bedienelement #{schluessel} steht in mehreren Katalogen (#{File.basename(datei)})"
          end

          alle[schluessel.to_s] = { icon: eintrag["icon"].to_s,
                                    label: eintrag["label"].to_s,
                                    dynamisch: eintrag["dynamisch"] == true }
        end
      end.freeze
    end
  end
end
