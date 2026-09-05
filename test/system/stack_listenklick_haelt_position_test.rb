require "application_system_test_case"

# #1501 R3: derselbe Fehler wie R2, aber im ZWEITEN Pfad — dem Listen-Klick.
#
# R2 hat `_oeffneNeben` repariert (Modifier-Klick auf einen Verweis). Der
# haeufigste Weg im Stack ist aber ein anderer: Zeile in einem Listen-Blade
# anklicken. Der laeuft ueber `_appendBladeAtUrl(mode: "replace_substack")`
# und hatte zwei Stellen, an denen R2 nicht wirkt:
#
#   1. `_replaceSubStackAfter` sammelt alles zwischen der Listen-Card und dem
#      naechsten Listen-Blade ein — OHNE Filter auf `.stack-card`. Folgt kein
#      weiteres Listen-Blade, laeuft die Schleife bis ans Container-Ende und
#      nimmt den stehenden `.stack-end-spacer` (#1091 v4) mit. Der Spacer ist
#      genau das, was rechts den Freiraum haelt; ohne ihn faellt `scrollWidth`,
#      die maximale Scrollposition sinkt unter die aktuelle, und der BROWSER
#      kappt `scrollLeft`. Ein gekappter Wert ist weg.
#   2. Anders als der reparierte Zweig merkt sich dieser Pfad die Position
#      vorher nicht und stellt sie danach nicht wieder her.
#
# Sichtbar wird das als aufklappende Spines links: Man scrollt die Liste auf
# ihren Ruecken weg, klickt eine andere Zeile — und die Liste steht wieder
# voll da. (Hinweis auf die Klasse von immoos_builder, 2026-09-02, der den
# Spacer bei sich im anderen Pfad mitentfernt.)
class StackListenklickHaeltPositionTest < ApplicationSystemTestCase
  setup do
    @hans = create_human
    grant(@hans, "KnowledgeItem", %w[read create update])

    @ada = KnowledgeItem.create!(uuid: SecureRandom.uuid, title: "Ada Lovelace",
                                 item_type: "person", creator: @hans,
                                 file_path: "x/ada.md", content_hash: "h-ada")
    @bob = KnowledgeItem.create!(uuid: SecureRandom.uuid, title: "Bob Bachmann",
                                 item_type: "person", creator: @hans,
                                 file_path: "x/bob.md", content_hash: "h-bob")
    login_as(@hans)
  end

  # Gemessen wird der sichtbare Streifen als ABSTAND ZWEIER CARD-KANTEN, nicht
  # ueber Klassennamen — so haengt der Test nicht daran, wie eine eingeklappte
  # Card gerade heisst.
  MASS = <<~JS.freeze
    (() => {
      const c = document.getElementById("blade_stack_container");
      const k = Array.from(c.querySelectorAll(".stack-card")).map(x => x.getBoundingClientRect());
      return {
        scroll:   Math.round(c.scrollLeft),
        streifen: k.length > 1 ? Math.round(k[1].left - k[0].left) : null,
        cards:    k.length,
        spacer:   c.querySelector(":scope > .stack-end-spacer") ? 1 : 0
      };
    })()
  JS

  def messen = page.evaluate_script(MASS)

  test "ein Listen-Klick laesst den Stapel stehen" do
    page.driver.resize_window(1600, 900)
    visit "/knowledge_items?stack=list:persons,#{@ada.uuid}"
    assert_selector "article.stack-card[data-uuid='#{@ada.uuid}']", wait: 10

    # Ein Stueck nach rechts — so weit, dass eine Position da ist, die
    # verlorengehen kann, aber NICHT so weit, dass die Liste zum Spine wird.
    #
    # Das ist die Bedingung, an der mein erster Anlauf gescheitert ist: Ganz
    # rechts ist die Listen-Card auf 28px eingeklappt und ihre Zeilen sind
    # unsichtbar. Cuprite klickt sie trotzdem — der Browser fokussiert das
    # Element und scrollt es dabei selbst ins Bild. Der Test mass dann diesen
    # Fokus-Sprung (388 → 0), nicht den Umbau, und war rot, egal was der
    # Umbau tat. Ein Nutzer kann keine unsichtbare Zeile anklicken.
    page.execute_script(<<~JS)
      const c = document.getElementById("blade_stack_container");
      c.scrollLeft = 100;
    JS
    sleep 0.5
    vorher = messen
    assert_operator vorher["scroll"], :>, 0,
                    "Vorbedingung: der Stapel muss verschoben sein, sonst misst der Test nichts"

    # Vorbedingung 2: die Zeile muss WIRKLICH SICHTBAR sein — sonst misst der
    # Test wieder den Fokus-Sprung des Browsers statt des Umbaus.
    sichtbar = page.evaluate_script(<<~JS)
      (() => {
        const c = document.getElementById("blade_stack_container");
        const a = Array.from(c.querySelectorAll("a,button"))
                       .find(x => (x.textContent || "").includes("Bob Bachmann"));
        if (!a) return -1;
        const cr = c.getBoundingClientRect(), r = a.getBoundingClientRect();
        return Math.round(Math.min(r.right, cr.right) - Math.max(r.left, cr.left));
      })()
    JS
    assert_operator sichtbar, :>, 50,
                    "Vorbedingung: die zu klickende Zeile muss sichtbar sein (#{sichtbar}px), " \
                    "sonst scrollt der Browser sie beim Fokussieren selbst ins Bild"

    # Vorbedingung 3: Faellt das Maximum OHNE die zu ersetzende Card unter die
    # aktuelle Position? Nur dann kappt der Browser ueberhaupt.
    ohne = page.evaluate_script(<<~JS)
      (() => {
        const c = document.getElementById("blade_stack_container");
        const k = c.querySelector('.stack-card[data-uuid="#{@ada.uuid}"]');
        return Math.round(c.scrollWidth - k.getBoundingClientRect().width - c.clientWidth);
      })()
    JS
    assert_operator ohne, :<, vorher["scroll"],
                    "Vorbedingung: ohne die ersetzte Card (#{ohne}) muss das Maximum unter " \
                    "der aktuellen Position (#{vorher['scroll']}) liegen — sonst kappt nichts"

    click_on "Bob Bachmann"
    assert_selector "article.stack-card[data-uuid='#{@bob.uuid}']", wait: 15
    assert_no_selector "article.stack-card[data-uuid='#{@ada.uuid}']", wait: 10
    sleep 0.8

    nachher = messen
    assert_equal 2, nachher["cards"], "ersetzt, nicht angehaengt"
    assert_in_delta vorher["scroll"], nachher["scroll"], 2,
                    "der Stapel darf beim Listen-Klick nicht wegspringen " \
                    "(#{vorher['scroll']} → #{nachher['scroll']})"
  end
end
