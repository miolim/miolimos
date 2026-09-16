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

  # #1648 (aus immoOS #1645 übernommen). Hans dort: „Wenn ich
  # /dashboard?start=empty aufrufe, kommt immer eine automatische Weiterleitung
  # auf …&stack=… statt des leeren Dashboards."
  #
  # Der gemerkte Stack kommt aus ZWEI Quellen, und der Test oben deckte nur
  # eine ab (Session-/localStorage unter „stack…"). Die zweite ist die
  # VERLAUFS-History: Sie fragte nur, ob gerade gar keine Card steht — und beim
  # leeren Start steht eben keine. Deshalb hier nicht in den Browser-Speicher
  # schreiben, sondern den Weg des Nutzers gehen: erst normal mit einer Card
  # arbeiten, dann leer starten.
  test "#1648: leerer Start bleibt leer, auch mit Verlauf in der History" do
    # Bewusst OHNE Liste als erste Card: Der Verlauf hat zwei Behälter
    # (LIST_HISTORY_KEY / PAGE_HISTORY_KEY). Ist die erste Card eine Liste,
    # landet der Eintrag im Listen-Behälter — und den liest der leere Start
    # gar nicht. Getroffen wird hier der Seiten-Behälter.
    visit "/dashboard?stack=task:#{@task.id}"
    assert_selector "#blade_stack_container [data-uuid='task:#{@task.id}']", wait: 5

    visit "/dashboard?start=empty"
    sleep 1

    # Erst hier prüfbar: Geschrieben wird der Verlauf beim VERLASSEN der Seite
    # (turbo:before-visit/beforeunload), nicht bei jeder Änderung. Ohne diese
    # Vorbedingung bewiese ein leeres Ergebnis nichts.
    assert_includes page.evaluate_script(
      "localStorage.getItem('#{DashboardController::PAGE_HISTORY_KEY}') || ''"
    ), "task:#{@task.id}", "Vorbedingung: der Verlaufs-Eintrag muss existieren"
    assert_equal [], cards, "der leere Start darf auch den Verlauf nicht nachladen"
    assert_no_match(/stack=/, page.current_url,
                    "und sich keinen Stack in die Adresszeile schreiben")
  end
end
