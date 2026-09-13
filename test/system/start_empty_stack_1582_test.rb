require "application_system_test_case"

# #1582 (Hans): „Es soll auch möglich sein, mit einem leeren Stack, also ohne
# voreingestellte Card zu starten."
#
# Der Server rendert beim leeren Start keine Card — das prüft der Controller-
# Test. Hier geht es um den Browser: Der Blade-Stack lädt ohne ?stack= sonst
# den gemerkten Stack aus sessionStorage/localStorage nach
# (_restoreSessionStackIfNeeded). Die Gegenprobe zeigt, dass dieser Restore
# im Test überhaupt greift — sonst bewiese das leere Ergebnis nichts.
class StartEmptyStack1582Test < ApplicationSystemTestCase
  setup do
    @hans = create_human
    grant(@hans, "Task", %w[read])
    grant(@hans, "Topic", %w[read])
    grant(@hans, "KnowledgeItem", %w[read])
    grant(@hans, "Communication", %w[read])
    grant(@hans, "Actor", %w[read update])
    @task = Task.create!(title: "Gemerkte Aufgabe", creator: @hans, assignee: @hans, status: :open)
    login_as(@hans)
  end

  def cards
    page.evaluate_script("Array.from(document.querySelectorAll('#blade_stack_container [data-uuid]')).map(e => e.dataset.uuid)")
  end

  # Gemerkten Stack in beiden Browser-Speichern ablegen, unter jedem Schlüssel,
  # den der Blade-Stack für die Dashboard-Seite liest.
  def merke_stack!
    page.execute_script(<<~JS)
      const wert = "task:#{@task.id}"
      for (const store of [sessionStorage, localStorage]) {
        for (let i = 0; i < store.length; i++) {
          const k = store.key(i)
          if (/stack/i.test(k)) store.setItem(k, wert)
        }
      }
    JS
  end

  test "leerer Start bleibt leer, auch mit gemerktem Stack im Browser" do
    # Gegenprobe: normales Dashboard ohne Params stellt den gemerkten Stack her.
    visit "/dashboard?stack=list:dashboard,task:#{@task.id}"
    assert_selector "#blade_stack_container [data-uuid='task:#{@task.id}']", wait: 5
    merke_stack!

    @hans.update_preferences("start_stack" => "empty")
    visit "/"
    assert_current_path "/dashboard?start=empty"
    sleep 1

    assert_equal [], cards, "leerer Start darf keine Card nachladen"
  end
end
