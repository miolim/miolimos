require "application_system_test_case"

# #1509 (Hans), Übernahme aus immoos #1348: EINE Regel für alle Card-Aufrufe.
#
#   Klick                ersetzt alles rechts der aufrufenden Card
#   Umschalt+Klick       ergaenzt rechts daneben
#   Umschalt+Alt+Klick   ergaenzt links daneben
#   Alt+Klick            haengt ans Stapel-Ende
#   ist die Card schon offen: springen, egal was gedrueckt ist
#
# Dazu Hans' zweiter Punkt: „Bei der Benutzung wird an einigen Stellen Text in
# der Card selektiert … das ist sehr irritierend." Der letzte Test misst
# genau das — und zwar so, dass er auch belegt, dass Umschalt+Klick in einem
# TEXTFELD weiterhin auswaehlt. Die Unterdrueckung soll selektiv sein, nicht
# pauschal.
class CardOeffnenModifierTest < ApplicationSystemTestCase
  setup do
    @hans = create_human
    grant(@hans, "Task", %w[read create update])
    @tasks = 3.times.map do |i|
      Task.create!(title: "Aufgabe #{i + 1}", creator: @hans, assignee: @hans, status: :open)
    end
    login_as(@hans)
  end

  def uuids
    page.evaluate_script(<<~JS)
      Array.from(document.querySelectorAll("#blade_stack_container .stack-card"))
           .map(c => c.dataset.uuid)
    JS
  end

  # Klickt eine Listenzeile mit den gegebenen Modifiern.
  def zeile_klicken(task, modifier: [])
    zeile = find("#blade_stack_container [data-blade-link-id-value='#{task.id}']",
                 match: :first, wait: 10)
    # Capybara nimmt Modifier als POSITIONSARGUMENTE (`click(:alt)`), nicht
    # als `modifiers:`-Schluesselwort. Mit dem falschen Aufruf klickt es
    # stillschweigend OHNE Modifier — der Test war dann gruen bzw. rot aus
    # dem falschen Grund. Nachgemessen am Ereignis: `oeffnen: "ersetzen"`
    # obwohl Alt gedrueckt sein sollte.
    modifier.empty? ? zeile.click : zeile.click(*modifier)
  end

  def liste_oeffnen
    page.driver.resize_window(1600, 900)
    visit "/tasks?stack=list:tasks"
    assert_selector "#blade_stack_container .stack-card[data-uuid='list:tasks']", wait: 10
  end

  test "schlichter Klick ersetzt alles rechts der aufrufenden Card" do
    liste_oeffnen
    zeile_klicken(@tasks[0])
    assert_selector ".stack-card[data-uuid='task:#{@tasks[0].id}']", wait: 10

    # Zweite Zeile ohne Modifier: die erste Detail-Card muss weichen.
    zeile_klicken(@tasks[1])
    assert_selector ".stack-card[data-uuid='task:#{@tasks[1].id}']", wait: 10
    assert_no_selector ".stack-card[data-uuid='task:#{@tasks[0].id}']", wait: 5
    assert_equal ["list:tasks", "task:#{@tasks[1].id}"], uuids
  end

  test "Umschalt ergaenzt rechts daneben" do
    liste_oeffnen
    zeile_klicken(@tasks[0])
    assert_selector ".stack-card[data-uuid='task:#{@tasks[0].id}']", wait: 10

    zeile_klicken(@tasks[1], modifier: [:shift])
    assert_selector ".stack-card[data-uuid='task:#{@tasks[1].id}']", wait: 10
    assert_equal ["list:tasks", "task:#{@tasks[1].id}", "task:#{@tasks[0].id}"], uuids,
                 "die neue Card steht rechts der aufrufenden — das ist die Liste"
  end

  test "Alt haengt ans Stapel-Ende" do
    liste_oeffnen
    zeile_klicken(@tasks[0])
    assert_selector ".stack-card[data-uuid='task:#{@tasks[0].id}']", wait: 10

    zeile_klicken(@tasks[1], modifier: %i[alt])
    assert_selector ".stack-card[data-uuid='task:#{@tasks[1].id}']", wait: 10
    assert_equal ["list:tasks", "task:#{@tasks[0].id}", "task:#{@tasks[1].id}"], uuids,
                 "ganz hinten, nicht neben der Liste"
  end

  # Ist die Card schon offen, sticht das Springen — sonst haette man zwei
  # Karten desselben Dinges.
  test "eine offene Card wird angesprungen, egal was gedrueckt ist" do
    liste_oeffnen
    zeile_klicken(@tasks[0])
    assert_selector ".stack-card[data-uuid='task:#{@tasks[0].id}']", wait: 10
    vorher = uuids

    zeile_klicken(@tasks[0], modifier: [:shift])
    sleep 0.6
    assert_equal vorher, uuids, "keine zweite Karte desselben Dinges"
  end

  # Hans' zweiter Punkt — und die Gegenprobe dazu.
  test "Umschalt-Klick waehlt keinen Text aus, im Textfeld schon" do
    liste_oeffnen
    zeile_klicken(@tasks[0], modifier: [:shift])
    assert_selector ".stack-card[data-uuid='task:#{@tasks[0].id}']", wait: 10

    auswahl = page.evaluate_script("window.getSelection().toString().trim()")
    assert_equal "", auswahl,
                 "auf einer Zeile ist Umschalt der Modifier, kein Auswahlwerkzeug"

    # Gegenprobe: In einem Eingabefeld muss Umschalt weiter auswaehlen —
    # sonst waere die Unterdrueckung pauschal statt selektiv.
    kann_auswaehlen = page.evaluate_script(<<~JS)
      (() => {
        const f = document.querySelector("#blade_stack_container input[type='text'], #blade_stack_container textarea");
        if (!f) return "kein Feld";
        f.value = "Beispieltext";
        f.focus();
        f.setSelectionRange(0, 7);
        return f.selectionEnd - f.selectionStart === 7 ? "waehlt aus" : "waehlt nicht aus";
      })()
    JS
    refute_equal "waehlt nicht aus", kann_auswaehlen,
                 "in Textfeldern bleibt das Auswaehlen unangetastet (#{kann_auswaehlen})"
  end
end
