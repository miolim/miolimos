require "application_system_test_case"

# #1161: Das Topbar-Suchfeld leerte sich beim Tippen von selbst. Ursache:
# Seit #1109 sitzt der quick-create-Controller auf dem ganzen <header>;
# sein turbo:submit-end-Handler resettete jedes erfolgreiche Form im
# Header — also auch das Suchformular nach jeder debounced Submission.
# Die Treffer (Frame ausserhalb des Headers) blieben dabei stehen.
class TopbarSearchTest < ApplicationSystemTestCase
  test "Suchfeld behaelt den getippten Text, wenn Treffer eintreffen" do
    hans = create_human
    grant(hans, "Task",          %w[read create update delete])
    grant(hans, "KnowledgeItem", %w[read])
    grant(hans, "Communication", %w[read])
    Task.create!(creator: hans, title: "Migration Datenbank",
                 description: "Wichtig", status: :open)

    login_as(hans)
    fill_in "q", with: "Migration"

    # Debounce (150ms) + Frame-Roundtrip abwarten: erst wenn die Treffer
    # da sind, hat turbo:submit-end gefeuert — genau dann schlug #1161 zu.
    assert_selector "#search_results", text: "Migration Datenbank", wait: 5

    assert_equal "Migration", find_field("q").value,
      "Suchfeld darf nach dem Eintreffen der Treffer nicht geleert werden"
  end

  test "Quick-Create-Slot-Form wird nach Submit weiter geleert und geschlossen" do
    hans = create_human
    grant(hans, "Task", %w[read create update delete])

    login_as(hans)
    # Task-Slot oeffnen (g t — der Shortcut-Weg ist fokus-unabhaengig
    # stabiler als der konfigurierbare Icon-Klick, #1109).
    page.driver.browser.keyboard.type("g", "t")
    slot_input = find("input#quick_create_task_title", wait: 5)
    slot_input.fill_in(with: "Neue Aufgabe aus Slot")
    slot_input.send_keys(:enter)

    # Nach erfolgreichem Submit: Slot zu (#301) und Form geleert (#318).
    assert_no_selector "[data-quick-create-target='slot'][data-slot='task']:not(.hidden)", wait: 5
    assert Task.exists?(title: "Neue Aufgabe aus Slot"), "Task sollte angelegt sein"
  end
end
