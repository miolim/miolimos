require "application_system_test_case"

# #1496 (aus immoos #1343 uebernommen, Farbe angepasst).
#
# Hans: „Bitte die Hervorhebung des aktiven Stacks in der Sidebar uebernehmen.
# Die Farbe dabei so anpassen, dass sie dem Hintergrund entspricht, der einmal
# um den Stack herum sichtbar ist."
#
# Genau das prueft der erste Test — und zwar als VERGLEICH, nicht als
# Farbwert: Die aktive Zeile und die Flaeche um die Karten muessen dieselbe
# Farbe haben. Stuende hier `rgb(248, 250, 252)`, waere der Test beim naechsten
# Anfassen des Seitenhintergrunds still falsch, ohne dass jemand es merkt.
class SidebarAktiveZeileTest < ApplicationSystemTestCase
  setup do
    @hans = create_human
    grant(@hans, "Task", %w[read])
    grant(@hans, "KnowledgeItem", %w[read])
    login_as(@hans)
  end

  # Liefert die tatsaechlich gemalte Hintergrundfarbe: Bei einem
  # durchsichtigen Element steigt sie zu dem Vorfahren auf, der wirklich
  # faerbt. Ohne das misst man `rgba(0, 0, 0, 0)` und vergleicht Nichts.
  GEMALT = <<~JS.freeze
    (sel) => {
      let el = document.querySelector(sel);
      while (el) {
        const f = getComputedStyle(el).backgroundColor;
        if (f && f !== "rgba(0, 0, 0, 0)" && f !== "transparent") return f;
        el = el.parentElement;
      }
      return null;
    }
  JS

  def farbe_von(selektor)
    page.evaluate_script("(#{GEMALT})(#{selektor.to_json})")
  end

  test "die aktive Zeile traegt die Farbe der Flaeche um den Stack" do
    visit "/tasks"
    assert_selector "aside nav a", wait: 10

    aktiv = page.evaluate_script(<<~JS)
      (() => {
        const a = Array.from(document.querySelectorAll("aside nav a"))
                       .find(x => (x.getAttribute("href") || "").startsWith("/tasks"));
        if (!a) return null;
        // #1509: Bis zum Ausbau des Plus lag der Link in einer Umhuellung, und
        // DIE trug die Farbe. Jetzt ist der Link die Zeile. Die alte Heuristik
        // („nimm das Elternelement, wenn es `flex` hat") griff danach auf das
        // <nav> — das ist `flex flex-col` und faerbt nicht: Der Test mass
        // `rgba(0, 0, 0, 0)` und meldete einen Regress, den es nicht gab.
        return getComputedStyle(a).backgroundColor;
      })()
    JS

    assert aktiv, "die aktive Zeile muss auffindbar sein"
    assert_equal farbe_von("body"), aktiv,
                 "die aktive Zeile soll die Farbe tragen, auf der die Karten liegen"
  end

  test "eine nicht aktive Zeile bleibt dunkel" do
    visit "/tasks"
    assert_selector "aside nav a", wait: 10

    befund = page.evaluate_script(<<~JS)
      (() => {
        const links = Array.from(document.querySelectorAll("aside nav a"));
        const andere = links.find(x => !(x.getAttribute("href") || "").startsWith("/tasks"));
        if (!andere) return null;
        return getComputedStyle(andere).backgroundColor;
      })()
    JS

    refute_equal farbe_von("body"), befund,
                 "nur die aktive Zeile ist hell — sonst waere die Hervorhebung keine"
  end

  # Der Streifen soll bis an beide Kanten laufen. Der schmale Scrollbalken lag
  # AUSSERHALB des Inhalts und liess sich von keiner Zeile einfaerben; rechts
  # blieb zwangslaeufig ein dunkler Rest. Deshalb ist er unsichtbar — was man
  # daran misst, dass Inhalts- und Aussenbreite der Leiste gleich sind.
  test "die Leiste hat keinen sichtbaren Scrollbalken mehr" do
    visit "/tasks"
    assert_selector "aside nav", wait: 10

    luecke = page.evaluate_script(<<~JS)
      (() => {
        const nav = document.querySelector("aside nav");
        return Math.round(nav.offsetWidth - nav.clientWidth);
      })()
    JS
    assert_equal 0, luecke,
                 "ein Balken von #{luecke}px waere der dunkle Streifen am rechten Rand"
  end
end
