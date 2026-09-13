require "test_helper"

# #1576: Die Shortcut-Liste (shortcut_help_controller.js) holt jede Ueberschrift,
# jede Mausgesten-Beschriftung und jede Beschreibung per window.t aus
# js.shortcut_help.*. Fehlt ein Schluessel in einer Sprache, stuende im Modal der
# rohe Schluessel. Gelesen wird die JS-Datei selbst, damit ein neuer Eintrag dort
# ohne Sprachdatei-Zeile sofort auffaellt.
class ShortcutHelpLocalesTest < ActiveSupport::TestCase
  SOURCE = Rails.root.join("app/javascript/controllers/shortcut_help_controller.js")

  def schluessel
    File.read(SOURCE).scan(/"shortcut_help\.([a-z_]+)"/).flatten.uniq
  end

  test "jeder Text der Shortcut-Liste steht auf Deutsch und Englisch" do
    keys = schluessel
    assert_operator keys.size, :>=, 40, "die Liste wird aus der JS-Datei gelesen"

    %i[de en].each do |sprache|
      fehlend = keys.reject { |k| I18n.exists?("js.shortcut_help.#{k}", sprache) }
      assert_empty fehlend, "#{sprache}: js.shortcut_help.* fehlt fuer #{fehlend.inspect}"
    end
  end

  test "die Mausklick-Modifier stehen in der Liste" do
    keys = schluessel
    %w[key_click key_shift_click key_shift_alt_click key_alt_click key_mod_click].each do |k|
      assert_includes keys, k
    end
  end

  test "die Liste ist mit Zwischenueberschriften gegliedert" do
    gruppen = schluessel.grep(/\Agroup_/).reject { |k| k.end_with?("_note") }
    assert_operator gruppen.size, :>=, 4
  end
end
