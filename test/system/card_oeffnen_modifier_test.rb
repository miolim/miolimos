require "application_system_test_case"

# #1642 (Hans): „Wenn man die UMSCHALT-Taste beim Klick gedrückt hält, erscheint
# ein Kontextmenü … Damit muss man sich nicht die unterschiedlichen Modifier
# merken, sondern nur einen." — Variante B: NUR noch das Menü, die
# Alt-Kombinationen aus #1509 entfallen.
#
#   Klick            ersetzt alles rechts der aufrufenden Card
#   Umschalt+Klick   Menü: rechts ersetzen · links · rechts · ans Ende
#   Alt+Klick        wirkt jetzt wie ein schlichter Klick
#   Cmd/Strg         gehört dem Browser
#
# Dazu Hans' Punkt aus #1509: „Bei der Benutzung wird an einigen Stellen Text in
# der Card selektiert … das ist sehr irritierend." Der letzte Test misst das —
# und belegt, dass Umschalt+Klick in einem TEXTFELD weiterhin auswählt.
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
  # Capybara nimmt Modifier als POSITIONSARGUMENTE (`click(:alt)`), nicht als
  # `modifiers:`-Schlüsselwort — mit dem falschen Aufruf klickt es still ohne
  # Modifier, und der Test wäre grün aus dem falschen Grund.
  def zeile_klicken(task, modifier: [])
    zeile = find("#blade_stack_container [data-blade-link-id-value='#{task.id}']",
                 match: :first, wait: 10)
    modifier.empty? ? zeile.click : zeile.click(*modifier)
  end

  # Umschalt+Klick öffnet das Menü; dann den gewünschten Eintrag wählen.
  def per_menue_oeffnen(task, art)
    zeile_klicken(task, modifier: [:shift])
    assert_selector "#blade_open_menu", wait: 5
    find("#blade_open_menu button[data-open-art='#{art}']").click
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

    zeile_klicken(@tasks[1])
    assert_selector ".stack-card[data-uuid='task:#{@tasks[1].id}']", wait: 10
    assert_no_selector ".stack-card[data-uuid='task:#{@tasks[0].id}']", wait: 5
    assert_equal ["list:tasks", "task:#{@tasks[1].id}"], uuids
  end

  test "Umschalt zeigt das Menü mit allen vier Öffnungsarten" do
    liste_oeffnen
    zeile_klicken(@tasks[0], modifier: [:shift])

    assert_selector "#blade_open_menu", wait: 5
    beschriftungen = all("#blade_open_menu button").map(&:text)
    assert_equal %w[ende rechts links ersetzen].map { |a| I18n.t("js.blade_open_menu.#{a}") },
                 beschriftungen
    assert page.has_no_css?(".stack-card[data-uuid='task:#{@tasks[0].id}']", wait: 2),
           "erst die Wahl öffnet die Karte"
  end

  test "Menü-Wahl „rechts“ öffnet rechts neben der aufrufenden Card" do
    liste_oeffnen
    zeile_klicken(@tasks[0])
    assert_selector ".stack-card[data-uuid='task:#{@tasks[0].id}']", wait: 10

    per_menue_oeffnen(@tasks[1], "rechts")
    assert_selector ".stack-card[data-uuid='task:#{@tasks[1].id}']", wait: 10
    assert_equal ["list:tasks", "task:#{@tasks[1].id}", "task:#{@tasks[0].id}"], uuids,
                 "die neue Card steht rechts der aufrufenden — das ist die Liste"
  end

  test "Menü-Wahl „am Ende“ hängt ans Stapel-Ende" do
    liste_oeffnen
    zeile_klicken(@tasks[0])
    assert_selector ".stack-card[data-uuid='task:#{@tasks[0].id}']", wait: 10

    per_menue_oeffnen(@tasks[1], "ende")
    assert_selector ".stack-card[data-uuid='task:#{@tasks[1].id}']", wait: 10
    assert_equal ["list:tasks", "task:#{@tasks[0].id}", "task:#{@tasks[1].id}"], uuids,
                 "ganz hinten, nicht neben der Liste"
  end

  test "Escape im Menü öffnet nichts" do
    liste_oeffnen
    vorher = uuids
    zeile_klicken(@tasks[0], modifier: [:shift])
    assert_selector "#blade_open_menu", wait: 5

    escape_druecken
    assert_no_selector "#blade_open_menu", wait: 5
    sleep 0.5
    assert_equal vorher, uuids, "abgebrochen heißt: nichts öffnen"
  end

  # #1642: Alt hat seine Sonderrolle verloren.
  test "Alt+Klick wirkt wie ein schlichter Klick" do
    liste_oeffnen
    zeile_klicken(@tasks[0])
    assert_selector ".stack-card[data-uuid='task:#{@tasks[0].id}']", wait: 10

    zeile_klicken(@tasks[1], modifier: [:alt])
    assert_no_selector "#blade_open_menu", wait: 3
    assert_selector ".stack-card[data-uuid='task:#{@tasks[1].id}']", wait: 10
    assert_equal ["list:tasks", "task:#{@tasks[1].id}"], uuids,
                 "ersetzt, statt ans Ende zu hängen"
  end

  # Ist die Card schon offen, sticht das Springen — sonst hätte man zwei
  # Karten desselben Dinges.
  test "eine offene Card wird angesprungen, egal was gewählt wird" do
    liste_oeffnen
    zeile_klicken(@tasks[0])
    assert_selector ".stack-card[data-uuid='task:#{@tasks[0].id}']", wait: 10
    vorher = uuids

    per_menue_oeffnen(@tasks[0], "rechts")
    sleep 0.6
    assert_equal vorher, uuids, "keine zweite Karte desselben Dinges"
  end

  # Hans' Punkt aus #1509 — und die Gegenprobe dazu.
  test "Umschalt-Klick wählt keinen Text aus, im Textfeld schon" do
    liste_oeffnen
    zeile_klicken(@tasks[0], modifier: [:shift])
    assert_selector "#blade_open_menu", wait: 5

    auswahl = page.evaluate_script("window.getSelection().toString().trim()")
    assert_equal "", auswahl,
                 "auf einer Zeile ist Umschalt der Modifier, kein Auswahlwerkzeug"
    escape_druecken

    # Gegenprobe: In einem Eingabefeld muss Umschalt weiter auswählen —
    # sonst wäre die Unterdrückung pauschal statt selektiv.
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
                 "in Textfeldern bleibt das Auswählen unangetastet (#{kann_auswaehlen})"
  end
end
