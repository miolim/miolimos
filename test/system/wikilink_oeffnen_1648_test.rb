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
    assert_equal %w[ersetzen links rechts ende].map { |a| I18n.t("js.blade_open_menu.#{a}") },
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

  test "ohne Umschalt hängt der Wikilink weiter ans Ende (#312)" do
    stack_oeffnen
    wikilink_klicken

    assert_selector ".stack-card[data-uuid='#{@ziel.uuid}']", wait: 10
    assert_no_selector "#blade_open_menu", wait: 2
    assert_equal [@quelle.uuid, @dritte.uuid, @ziel.uuid], uuids,
                 "ganz hinten, der Stack bleibt stehen"
  end

  test "Escape im Menü öffnet nichts" do
    stack_oeffnen
    vorher = uuids
    wikilink_klicken(modifier: [:shift])
    assert_selector "#blade_open_menu", wait: 5

    find("body").send_keys(:escape)
    assert_no_selector "#blade_open_menu", wait: 5
    sleep 0.5
    assert_equal vorher, uuids, "abgebrochen heißt: nichts öffnen"
  end
end
