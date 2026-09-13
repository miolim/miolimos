require "application_system_test_case"

# #1574 (Hans): „Auf der Sidebar sind die Icons aktuell nicht zentriert. Das
# resultiert vermutlich aus dem Wegfall des Plus-Icons. Bitte die Sidebar
# entsprechend schmaler machen, so dass die Icons horizontal zentriert
# angezeigt werden."
#
# Gemessen wird am gerenderten Layout, nicht an Klassennamen: Jede sichtbare
# Icon-Spalte der eingeklappten Leiste muss mittig stehen, egal ob sie im
# Kopf, im festen oder im scrollenden Bereich oder am Zahnrad sitzt. Aendert
# jemand spaeter Zeilen-Padding oder Icon-Spalte, ohne die Breite mitzuziehen,
# wird der Test rot.
class SidebarSchmalZentriertTest < ApplicationSystemTestCase
  setup do
    @hans = create_human
    grant(@hans, "Task", %w[read])
    grant(@hans, "KnowledgeItem", %w[read])
    login_as(@hans)
  end

  def eingeklappt_besuchen(pfad)
    visit pfad
    assert_selector "aside[data-controller='sidebar']", wait: 10
    page.execute_script("localStorage.setItem('sidebar.collapsed', 'true')")
    visit pfad
    assert_selector "aside[data-controller='sidebar'][data-persistent-collapsed='true']", wait: 10
    # Die Breite animiert (transition-all 200ms) — erst messen, wenn sie steht.
    sleep 0.4
  end

  test "in der schmalen Leiste stehen alle Icons mittig" do
    eingeklappt_besuchen "/tasks"

    befund = page.evaluate_script(<<~JS)
      (() => {
        const aside = document.querySelector("aside[data-controller='sidebar']");
        const box = aside.getBoundingClientRect();
        const spalten = Array.from(aside.querySelectorAll("span.w-5"))
          .filter(s => s.offsetParent !== null && s.getBoundingClientRect().width > 0);
        return {
          breite: Math.round(box.width),
          versatz: spalten.map(s => {
            const r = s.getBoundingClientRect();
            return Math.round((r.left + r.width / 2 - box.left) - box.width / 2);
          })
        };
      })()
    JS

    assert_operator befund["versatz"].size, :>=, 3, "es muessen Icons zum Messen da sein"
    daneben = befund["versatz"].reject { |v| v.abs <= 1 }
    assert_empty daneben,
                 "Leiste #{befund["breite"]}px breit, Icons um #{daneben.uniq.inspect}px aus der Mitte"
  end

  test "der Platzhalter haelt genau die Breite der schmalen Leiste" do
    eingeklappt_besuchen "/tasks"

    breiten = page.evaluate_script(<<~JS)
      (() => {
        const aside = document.querySelector("aside[data-controller='sidebar']");
        const platz = document.querySelector("[data-sidebar-placeholder]");
        return [Math.round(aside.getBoundingClientRect().width),
                Math.round(platz.getBoundingClientRect().width)];
      })()
    JS

    assert_equal breiten[0], breiten[1],
                 "sonst liegen die Karten unter der Leiste oder es bleibt eine Luecke"
  end
end
