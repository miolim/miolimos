require "application_system_test_case"

# #1496 (aus immoos #1457 uebernommen). Hans dort: „Bei Datumsfeldern muss man
# jedes Mal neu klicken, um dann den Monat und schliesslich das Jahr
# einzugeben. Und: Wenn man das Jahr nicht schnell genug eingibt, wird das
# Feld auch schon gespeichert."
#
# Ursache: `type="date"` meldet `change`, sobald ein VOLLSTAENDIGES Datum
# dasteht. Wer den Tag eines vorhandenen Datums aendert, hat sofort wieder ein
# vollstaendiges — es wird mitten in der Eingabe gespeichert, die Antwort
# tauscht das Feld aus, der Cursor ist weg.
#
# Deshalb speichern solche Felder jetzt erst beim VERLASSEN. Genau das wird
# hier gemessen, und zwar an der Datenbank: Solange der Cursor im Feld steht,
# darf sich nichts geaendert haben.
class AutosaveDatumTest < ApplicationSystemTestCase
  setup do
    @hans = create_human
    grant(@hans, "Task", %w[read create update])
    @task = Task.create!(title: "Termin verschieben", creator: @hans, assignee: @hans,
                         status: :open, due_date: Date.new(2026, 9, 1))
    login_as(@hans)
  end

  # Das Datumsfeld steckt in einer aufklappbaren Zeile (picker-toggle): Die
  # Zeile zeigt zunaechst nur den Wert, das Eingabefeld ist versteckt. Erst
  # der Klick auf die Zeile macht es sichtbar.
  # Zwei Huellen liegen ueber dem Feld: Der Details-Bereich der Card ist
  # zusammengeklappt (die Zeilen messen dann 0x0 und gelten als unsichtbar),
  # und in der Zeile selbst steckt das Eingabefeld hinter einem Umschalter.
  # Beides muss auf, sonst findet der Test nichts — und ein Test, der am
  # geschlossenen Bereich scheitert, sagt nichts ueber das Speichern.
  def datumsfeld
    assert_selector "article.stack-card", wait: 10
    find("article.stack-card [data-action~='click->tri-disclosure#cycle']", match: :first).click
    # Die Zeile ueber ihr Feld suchen, nicht ueber die Position: Die erste
    # Umschalt-Zeile ist die Zustaendigkeit, nicht das Datum.
    zeile = all("article.stack-card [data-controller~='picker-toggle']", wait: 10)
              .find { |r| r.has_css?("input[name*='due_date']", visible: :all) }
    assert zeile, "die Zeile mit dem Faelligkeitsdatum muss es geben"
    zeile.click
    find("article.stack-card input[type='date'][name*='due_date']", wait: 10)
  end

  test "waehrend der Eingabe wird nicht gespeichert, beim Verlassen schon" do
    visit "/tasks?stack=task:#{@task.id}"
    feld = datumsfeld

    # Mit einem echten Tastendruck arbeiten, nicht mit `set`: Cuprites `set`
    # verlaesst das Feld danach (nachgemessen — der Fokus liegt anschliessend
    # auf BODY). Dann greift die Bremse zu Recht nicht, und der Test haette
    # gemessen, wie Capybara tippt, nicht wie die Anwendung speichert.
    # Pfeil-hoch erhoeht das Segment unter dem Cursor: echtes change-Ereignis,
    # Fokus bleibt im Feld — genau Hans' Lage.
    feld.click
    feld.send_keys(:up)
    assert_equal "INPUT", page.evaluate_script("document.activeElement.tagName"),
                 "der Cursor muss im Feld bleiben, sonst misst der Test etwas anderes"
    sleep 1.0

    assert_equal Date.new(2026, 9, 1), @task.reload.due_date,
                 "solange der Cursor im Feld steht, darf nichts gespeichert sein"

    # Verlassen — jetzt soll gespeichert werden. NICHT mit Tab: In einem
    # Datumsfeld springt Tab zwischen Tag, Monat und Jahr, verlaesst das Feld
    # also gar nicht (nachgemessen: der Wert stand auf 2026-09-02, der Merker
    # der Bremse auf 1, und trotzdem kam kein focusout).
    page.execute_script("document.activeElement.blur()")
    assert_equal @task.reload.due_date, warte_auf_aenderung(Date.new(2026, 9, 1)),
                 "beim Verlassen wird der geaenderte Wert uebernommen"
    refute_equal Date.new(2026, 9, 1), @task.reload.due_date,
                 "und er ist wirklich ein anderer"
  end

  # Ohne Aenderung soll das Verlassen auch nichts ausloesen — sonst schriebe
  # jedes Durchgehen eines Formulars eine Runde Speichern los.
  test "Verlassen ohne Aenderung loest nichts aus" do
    visit "/tasks?stack=task:#{@task.id}"
    feld = datumsfeld
    vorher = @task.reload.updated_at

    feld.click
    page.execute_script("document.activeElement.blur()")
    sleep 1.0

    assert_equal vorher.to_i, @task.reload.updated_at.to_i,
                 "ein unveraendertes Feld wird beim Verlassen nicht gespeichert"
  end

  private

  def warte_auf_aenderung(alt, sekunden: 5)
    (sekunden * 10).times do
      jetzt = @task.reload.due_date
      return jetzt if jetzt != alt
      sleep 0.1
    end
    @task.reload.due_date
  end
end
