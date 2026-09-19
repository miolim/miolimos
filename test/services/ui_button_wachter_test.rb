require "test_helper"

# #1669 (Hans in immoOS #1664): „Könnte die Registrierung im Katalog nicht
# technische Voraussetzung für das Einfügen eines Buttons sein? Dann wäre der
# Wächter eventuell überflüssig."
#
# Fast. Der Helfer `ui_button` IST die Voraussetzung — ohne Katalogeintrag
# entsteht kein Knopf. Umgehen ließe er sich trotzdem: Wer ein rohes `<button>`
# mit einem Symbol darin schreibt, baut am Katalog vorbei. Genau das verbietet
# dieser Wächter, und nur das.
#
# Geprüft wird ausschließlich, was ein Mensch NICHT benennen kann: Knöpfe und
# Aufklapper ohne NAMEN — ohne Beschriftung, oder mit einem bloßen Zeichen als
# Beschriftung (#1669). Ein Knopf mit Wort trägt seinen Namen selbst.
#
# Die Erkennung steckt in UiButtonPruefung und ist dort einzeln geprüft — sie
# hat zweimal danebengelegen, als sie hier im Test wohnte.
class UiButtonWachterTest < ActiveSupport::TestCase
  # RÜCKSTAND: Die Umstellung läuft in Etappen (#1669 S2). Die Liste darf nur
  # schrumpfen; neue Dateien landen NIE darin, sie werden gleich mit
  # `ui_button` gebaut.
  RUECKSTAND = File.readlines(Rails.root.join("test/fixtures/files/ui_button_rueckstand.txt"),
                              chomp: true).reject { |z| z.blank? || z.start_with?("#") }.freeze

  def stellen(pfad) = UiButtonPruefung.offene_stellen(File.read(pfad))

  test "#1669: kein namenloser Knopf am Katalog vorbei" do
    offen = {}
    Dir.glob(Rails.root.join("app/views/**/*.erb")).sort.each do |pfad|
      relativ = Pathname.new(pfad).relative_path_from(Rails.root).to_s
      zeilen = stellen(pfad)
      offen[relativ] = zeilen if zeilen.any? && !RUECKSTAND.include?(relativ)
    end

    assert_empty offen,
                 "Namenlose Knöpfe ohne Kennung (bitte ui_button verwenden, Katalog: " \
                 "config/ui_elemente.yml):\n" +
                 offen.map { |datei, zeilen| "  #{datei}: Zeile #{zeilen.join(', ')}" }.join("\n")
  end

  # Der Rückstand darf nur schrumpfen: Steht eine Datei darin, obwohl sie längst
  # sauber ist, verdeckt sie kommende Fehler.
  test "#1669: der Rückstand enthält keine erledigten Dateien" do
    erledigt = RUECKSTAND.select do |relativ|
      pfad = Rails.root.join(relativ)
      pfad.exist? && stellen(pfad).empty?
    end

    assert_empty erledigt,
                 "Diese Dateien sind umgestellt — bitte aus " \
                 "test/fixtures/files/ui_button_rueckstand.txt streichen:\n  #{erledigt.join("\n  ")}"
  end
end
