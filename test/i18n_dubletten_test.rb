require "test_helper"

# #1648 (aus immoOS #1456 übernommen). Dort fiel es als „Translation missing"
# auf: Der Schlüssel STAND in der Datei — zweimal stand derselbe Block darin,
# und der zweite (aus einem Merge) überschrieb den ersten samt allem, was nur
# dort stand. YAML meldet das nicht: Bei doppelten Schlüsseln gewinnt
# stillschweigend der letzte.
#
# Das ist die tückische Sorte Fehler, weil sie beim Zusammenführen entsteht —
# und miolimOS führt regelmäßig Stände aus dem Fork zurück. Deshalb prüft
# dieser Test die Dateien im ROHZUSTAND (über den Psych-Baum), nicht das
# geladene Ergebnis: Das geladene Ergebnis hat den Verlust ja schon hinter
# sich.
class I18nDublettenTest < ActiveSupport::TestCase
  DATEIEN = Rails.root.glob("config/locales/*.yml").freeze

  test "keine doppelten Schluessel in den Uebersetzungsdateien" do
    assert DATEIEN.any?, "es gibt Locale-Dateien zu pruefen"

    befunde = DATEIEN.flat_map { |f| dubletten(Psych.parse(f.read)).map { |p| "#{f.basename}: #{p}" } }

    assert_empty befunde,
                 "doppelte Schluessel — der spaetere ueberschreibt den frueheren " \
                 "samt allem, was nur dort stand:\n  #{befunde.join("\n  ")}"
  end

  private

  # Läuft den Baum ab und meldet jeden Schlüssel, der in DEMSELBEN Mapping
  # mehrfach vorkommt — auf jeder Ebene, nicht nur ganz oben.
  def dubletten(node, pfad = [])
    return [] unless node.respond_to?(:children) && node.children

    eigene = []
    if node.is_a?(Psych::Nodes::Mapping)
      namen = node.children.each_slice(2).map { |k, _| k.respond_to?(:value) ? k.value : nil }.compact
      eigene = namen.tally.select { |_, n| n > 1 }.keys.map { |k| (pfad + [k]).join(".") }

      return eigene + node.children.each_slice(2).flat_map { |k, v|
        dubletten(v, pfad + [k.respond_to?(:value) ? k.value : "?"])
      }
    end

    eigene + node.children.flat_map { |c| dubletten(c, pfad) }
  end
end
