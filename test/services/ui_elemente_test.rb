require "test_helper"

# #1669: Der Katalog der Bedienelemente ist nur so viel wert, wie er mit der
# Wirklichkeit übereinstimmt. Drei Wächter halten ihn dort:
#   1. Jedes Symbol des Katalogs existiert auch als Datei.
#   2. Jede Beschriftung steht in de.yml UND en.yml (#619: mehrsprachig bauen).
#   3. Jeder Eintrag wird im Programm verwendet — keine Karteileichen.
class UiElementeTest < ActiveSupport::TestCase
  def quelltext
    @quelltext ||= Dir.glob(Rails.root.join("app/{views,helpers,controllers,services}/**/*.{erb,rb}"))
                      .reject { |p| p.end_with?("ui_elemente.rb") }
                      .map { |p| File.read(p) }.join("\n")
  end

  test "jedes Symbol des Katalogs existiert, jede Beschriftung in beiden Sprachen" do
    UiElemente.elemente.each do |schluessel, eintrag|
      assert_match UiElemente::SCHLUESSEL_RE, schluessel
      # #1672: Ein Eintrag OHNE Symbol ist erlaubt — ein beschrifteter Befehl
      # trägt seinen Namen als Text. Nur wer ein Symbol nennt, muss eines haben.
      if eintrag[:icon].present?
        pfad = Rails.root.join("app/views/shared/icons/_#{eintrag[:icon]}.html.erb")
        assert pfad.exist?, "#{schluessel}: Symbol #{eintrag[:icon]} gibt es nicht"
      end
      assert I18n.exists?(eintrag[:label], :de), "#{schluessel}: Beschriftung #{eintrag[:label]} fehlt in de.yml"
      assert I18n.exists?(eintrag[:label], :en), "#{schluessel}: Beschriftung #{eintrag[:label]} fehlt in en.yml"
    end
  end

  # Ein Eintrag gilt als benutzt, wenn ihn einer der beiden Helfer rendert.
  # Die Kennung darf auch aus einer Bedingung kommen (`ui_button (a ? :x : :y)`),
  # deshalb wird das Symbol selbst gesucht — es ist sprechend genug, dass ein
  # Fund kein Zufall ist. `dynamisch: true` heißt: Die Kennung entsteht erst
  # zur Laufzeit und ist im Quelltext nicht zu finden.
  test "jeder Eintrag des Katalogs wird im Programm verwendet" do
    unbenutzt = UiElemente.elemente.reject { |_, e| e[:dynamisch] }.keys.reject do |schluessel|
      quelltext.match?(/:#{Regexp.escape(schluessel)}\b/) ||
        quelltext.include?(%(data-ui-icon="#{schluessel}"))
    end
    assert_empty unbenutzt,
                 "Karteileichen im Katalog (nirgends per ui_icon/ui_button verwendet): #{unbenutzt.join(', ')}"
  end

  # Der Fork legt seine Kennungen in eine zweite Datei daneben. Eine Kennung in
  # BEIDEN wäre ein stiller Streit zwischen Basis und Fork.
  test "alle config/ui_elemente*.yml werden gelesen" do
    assert_includes UiElemente.dateien, Rails.root.join("config/ui_elemente.yml").to_s
  end

  test "eine Kennung in zwei Katalogen meldet sich" do
    doppel = Rails.root.join("config/ui_elemente.pruefung_test.yml")
    erster = UiElemente.elemente.keys.first
    skip "Katalog noch leer" if erster.blank?

    File.write(doppel, { erster => { "icon" => "x", "label" => "a.b" } }.to_yaml)
    assert_raises(UiElemente::Unbekannt) { UiElemente.neu_laden! }
  ensure
    File.delete(doppel) if doppel && File.exist?(doppel)
    UiElemente.neu_laden!
  end
end
