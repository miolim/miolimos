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

    # In den Freiraum hinter dem rechnerischen Content-Ende scrollen. Nur dort
    # steht ueberhaupt eine Position, die verlorengehen kann.
    page.execute_script(<<~JS)
      const c = document.getElementById("blade_stack_container");
      c.scrollLeft = c.scrollWidth;
    JS
    sleep 0.5
    vorher = messen
    assert_operator vorher["scroll"], :>, 0,
                    "Vorbedingung: der Stapel muss verschoben sein, sonst misst der Test nichts"
    assert_equal 1, vorher["spacer"], "Vorbedingung: der stehende Spacer muss da sein"

    # Vorbedingung des Fehlers ausdruecklich pruefen: Faellt die maximale
    # Scrollposition OHNE Spacer unter die aktuelle? Nur dann kappt der
    # Browser — sonst waere der Test bei anderer Fenstergroesse still gruen,
    # ohne je etwas gezeigt zu haben.
    ohne = page.evaluate_script(<<~JS)
      (() => {
        const c  = document.getElementById("blade_stack_container");
        const sp = c.querySelector(":scope > .stack-end-spacer");
        const b  = parseFloat(sp.style.width) || 0;
        return Math.round(c.scrollWidth - b - c.clientWidth);
      })()
    JS
    assert_operator ohne, :<, vorher["scroll"],
                    "Vorbedingung: ohne den Spacer (#{ohne}) muss das Maximum unter der " \
                    "aktuellen Position (#{vorher['scroll']}) liegen — sonst kappt nichts"

    # Andere Zeile in der Liste anklicken: ersetzt den Substack rechts davon.
    click_on "Bob Bachmann"
    assert_selector "article.stack-card[data-uuid='#{@bob.uuid}']", wait: 15
    assert_no_selector "article.stack-card[data-uuid='#{@ada.uuid}']", wait: 10
    sleep 0.8

    nachher = messen
    assert_equal 2, nachher["cards"], "ersetzt, nicht angehaengt"
    assert_equal 1, nachher["spacer"], "der stehende Spacer darf beim Ersetzen nicht mitentfernt werden"
    assert_in_delta vorher["scroll"], nachher["scroll"], 2,
                    "der Stapel darf beim Listen-Klick nicht wegspringen " \
                    "(#{vorher['scroll']} → #{nachher['scroll']})"
    assert_in_delta vorher["streifen"], nachher["streifen"], 2,
                    "und die weggescrollte Liste darf nicht wieder aufklappen " \
                    "(#{vorher['streifen']}px → #{nachher['streifen']}px)"
  end
end
