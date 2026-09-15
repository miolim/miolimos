require "application_system_test_case"

# #1631 (aus immoOS #1481 R2 übernommen). Hans dort: „Bitte generalisieren:
# Einfach immer anzeigen. Ggf. entsteht dann ein leerer Stack, aber das schadet
# ja auch nicht. Klick in die Sidebar öffnet ja wieder die erste Card."
#
# Vorher (#1496) war „Diese Karte und alle rechts davon schließen" an der ersten
# und an der letzten Karte gesperrt. Der Test geht ALLE Positionen durch, damit
# keine Sperre an einer davon still zurückkehrt.
class CloseMenuTest < ApplicationSystemTestCase
  setup do
    @hans = create_human
    grant(@hans, "Task", %w[read create update delete])
    login_as(@hans)
    @erste  = Task.create!(title: "Menü-Aufgabe A", creator: @hans, assignee: @hans, status: :open)
    @zweite = Task.create!(title: "Menü-Aufgabe B", creator: @hans, assignee: @hans, status: :open)
  end

  def stapel_oeffnen
    visit "/tasks?stack=list:tasks,task:#{@erste.id},task:#{@zweite.id}"
    assert page.has_css?("[data-uuid='task:#{@zweite.id}']", wait: 10), "Dritte Card fehlt"
  end

  test "#1631: „und alle rechts davon\" ist an jeder Position freigegeben" do
    stapel_oeffnen

    %W[list:tasks task:#{@erste.id} task:#{@zweite.id}].each do |uuid|
      assert_equal false, gesperrt?(uuid), "An #{uuid} muss der Befehl freigegeben sein"
    end
  end

  test "#1631: an der ersten Karte leert der Befehl den Stapel" do
    stapel_oeffnen

    menue_oeffnen("list:tasks")
    find("button", text: I18n.t("js.blade_stack.close_menu_right_of"), wait: 5).click

    assert page.has_no_css?(".stack-card", wait: 10), "Nach dem Schließen ab der ersten Karte bleibt keine Card übrig"
  end

  private

  def menue_oeffnen(uuid)
    all("[data-uuid='#{uuid}'] button[data-action~='click->blade-stack#closeCardMenu']", visible: :all).last.click
  end

  # Menü an der Card öffnen und den Zustand des unteren Eintrags lesen.
  def gesperrt?(uuid)
    menue_oeffnen(uuid)
    eintrag = find("button", text: I18n.t("js.blade_stack.close_menu_right_of"), wait: 5)
    zustand = eintrag.disabled?
    # Menü wieder zumachen, sonst trifft der nächste Klick den Dismiss-Handler.
    find("body").send_keys(:escape)
    zustand
  end
end
