require "application_system_test_case"

# #1648 (Hans): „Das Verhalten für Links sollte überall gleich sein. Auch
# Wikilinks sollte man über UMSCHALT Mausklick an der entsprechenden Position
# öffnen können."
#
# Umschalt+Klick auf einen Wikilink zeigt deshalb dasselbe Menü wie an allen
# anderen Klickwegen (#1642). OHNE Umschalt bleibt es beim Anhängen ans Ende —
# das ist Hans' Entscheidung aus #312 („der Stack bleibt stehen").
class WikilinkOeffnen1648Test < ApplicationSystemTestCase
  setup do
    @hans = create_human
    %w[KnowledgeItem Task Topic].each { |rt| grant(@hans, rt, %w[read create update]) }
    login_as(@hans)
    @ziel   = ki("Ziel-Eintrag", "Inhalt des Ziels")
    @quelle = ki("Quell-Eintrag", "Siehe [[Ziel-Eintrag]] für Details.")
    @dritte = ki("Dritter-Eintrag", "Noch ein Eintrag")
  end

  def ki(titel, body)
    FileProxy.create(actor: @hans, title: titel, item_type: :note, content: body,
                     topics: [], contacts: [], tags: [])
  end

  def uuids
    page.evaluate_script(<<~JS)
      Array.from(document.querySelectorAll("#blade_stack_container .stack-card")).map(c => c.dataset.uuid)
    JS
  end

  def stack_oeffnen
    page.driver.resize_window(1600, 900)
    visit "/knowledge_items?stack=#{@quelle.uuid},#{@dritte.uuid}"
    assert_selector ".stack-card[data-uuid='#{@quelle.uuid}']", wait: 10
    assert_selector ".stack-card[data-uuid='#{@quelle.uuid}'] a.wikilink", wait: 10
  end

  def wikilink_klicken(modifier: [])
    link = find(".stack-card[data-uuid='#{@quelle.uuid}'] a.wikilink", match: :first)
    modifier.empty? ? link.click : link.click(*modifier)
  end

  test "Umschalt+Klick auf einen Wikilink zeigt das Menü" do
    stack_oeffnen
    wikilink_klicken(modifier: [:shift])

    assert_selector "#blade_open_menu", wait: 5
    beschriftungen = all("#blade_open_menu button").map(&:text)
    assert_equal %w[ende rechts links ersetzen].map { |a| I18n.t("js.blade_open_menu.#{a}") },
                 beschriftungen
  end

  test "Menü-Wahl „rechts“ öffnet das Ziel neben der aufrufenden Card" do
    stack_oeffnen
    wikilink_klicken(modifier: [:shift])
    assert_selector "#blade_open_menu", wait: 5
    find("#blade_open_menu button[data-open-art='rechts']").click

    assert_selector ".stack-card[data-uuid='#{@ziel.uuid}']", wait: 10
    assert_equal [@quelle.uuid, @ziel.uuid, @dritte.uuid], uuids,
                 "das Ziel steht direkt rechts der aufrufenden Card"
  end

  # #1674 (Hans, 19.09.2026: „a" — überall dieselbe Regel). Bis dahin hielt dieser
  # Test das Gegenteil fest: ohne Umschalt ans Stapel-Ende (#312). Umgedreht
  # statt gelöscht — der Wikilink folgt jetzt der EINEN Öffnungsregel, wie jede
  # Listenzeile und jeder Verweis (und wie in immoOS seit #1348).
  test "ohne Umschalt ersetzt der Wikilink ab der aufrufenden Card" do
    stack_oeffnen
    wikilink_klicken

    assert_selector ".stack-card[data-uuid='#{@ziel.uuid}']", wait: 10
    assert_no_selector "#blade_open_menu", wait: 2
    assert_equal [@quelle.uuid, @ziel.uuid], uuids,
                 "die dritte Card weicht — wie bei jedem anderen Klick auch"
  end

  # Wer das Ziel weiter HINTEN haben will und den Stapel stehen lassen möchte
  # (das alte #312-Verhalten), wählt es im Umschalt-Menü.
  test "Menü-Wahl „ans Ende“ lässt den Stapel stehen und hängt hinten an" do
    stack_oeffnen
    wikilink_klicken(modifier: [:shift])
    assert_selector "#blade_open_menu", wait: 5
    find("#blade_open_menu button[data-open-art='ende']").click

    assert_selector ".stack-card[data-uuid='#{@ziel.uuid}']", wait: 10
    assert_equal [@quelle.uuid, @dritte.uuid, @ziel.uuid], uuids
  end

  # Cmd/Strg gehört dem Browser (neuer Tab) — der Stapel rührt sich nicht.
  test "Strg+Klick öffnet nichts im Stapel" do
    stack_oeffnen
    vorher = uuids
    page.execute_script(<<~JS, @quelle.uuid)
      const a = document.querySelector(`.stack-card[data-uuid='${arguments[0]}'] a.wikilink`)
      a.addEventListener("click", (e) => e.preventDefault(), { once: true })   // keinen Tab aufmachen
      a.dispatchEvent(new MouseEvent("click", { bubbles: true, cancelable: true, ctrlKey: true }))
    JS
    assert_no_selector ".stack-card[data-uuid='#{@ziel.uuid}']", wait: 2
    assert_equal vorher, uuids
  end

  test "Escape im Menü öffnet nichts" do
    stack_oeffnen
    vorher = uuids
    wikilink_klicken(modifier: [:shift])
    assert_selector "#blade_open_menu", wait: 5

    escape_druecken
    assert_no_selector "#blade_open_menu", wait: 5
    sleep 0.5
    assert_equal vorher, uuids, "abgebrochen heißt: nichts öffnen"
  end
end
