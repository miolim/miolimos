require "application_system_test_case"

# #1576 (Hans): „Es gibt eine Liste mit Shortcuts. Diese bitte ggf. sortieren
# durch Zwischenueberschriften gliedern. Ausserdem die Mausklick-Modifier mit
# aufnehmen."
#
# Geprueft wird das gerenderte Modal: die Gruppen-Ueberschriften aus der
# Sprachdatei, die Mausklick-Zeilen, und dass nirgends ein roher Schluessel
# stehen bleibt (window.t faellt bei fehlendem Key auf den Key zurueck).
class ShortcutHelpTest < ApplicationSystemTestCase
  setup do
    @hans = create_human
    grant(@hans, "Task", %w[read])
    grant(@hans, "KnowledgeItem", %w[read])
    login_as(@hans)
  end

  def modal_oeffnen
    visit "/tasks"
    assert_selector "[data-controller~='shortcut-help']", visible: :all, wait: 10
    page.execute_script("window.dispatchEvent(new Event('shortcut-help:open'))")
    assert_selector "#shortcut_help_modal", wait: 5
  end

  test "die Liste ist in Gruppen mit Ueberschrift gegliedert" do
    modal_oeffnen

    ueberschriften = all("#shortcut_help_modal h3").map(&:text)
    erwartet = %w[group_general group_edit group_cards group_open group_mouse]
                 .map { |k| I18n.t("js.shortcut_help.#{k}") }
    # h3 ist per CSS in Grossbuchstaben gesetzt; verglichen wird ohne Gross/Klein.
    assert_equal erwartet.map(&:downcase), ueberschriften.map(&:downcase)
  end

  test "die Mausklick-Modifier stehen mit Beschreibung im Modal" do
    modal_oeffnen

    within "#shortcut_help_modal" do
      %w[key_click key_shift_click key_shift_alt_click key_alt_click key_mod_click
         key_spine_right key_resize_mod_dblclick key_shift_wheel].each do |k|
        assert_text I18n.t("js.shortcut_help.#{k}")
      end
      assert_text I18n.t("js.shortcut_help.click_left")
      assert_text I18n.t("js.shortcut_help.group_open_note")
    end
  end

  test "kein roher Sprachschluessel im Modal" do
    modal_oeffnen

    text = find("#shortcut_help_modal").text
    refute_match(/shortcut_help\./, text)
  end
end
