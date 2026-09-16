require "application_system_test_case"

# #1576 (Hans): „Ja, bitte entsprechend angleichen." — die Dokumente-Liste folgt
# derselben Regel wie alle anderen Listen.
# #1642 (Hans): Diese Regel ist jetzt das Umschalt-Menü (Variante B):
#
#   Klick            ersetzt alles rechts der aufrufenden Card
#   Umschalt+Klick   Menü: rechts ersetzen · links · rechts · ans Ende
#   Alt+Klick        wirkt wie ein schlichter Klick (kein Modifier mehr)
#   Strg/Cmd+Klick   gehört dem Browser — die Zeile tut nichts
#   ist die Card schon offen: springen, egal was gedrückt ist
class DokumenteListeModifierTest < ApplicationSystemTestCase
  setup do
    @hans = create_human
    grant(@hans, "Document", %w[read create update])
    # Der DocumentsController gatet (noch) weich ueber Task (controller_resource_type),
    # und die Filter der Liste lesen KIs (Aussteller/Empfaenger).
    grant(@hans, "Task", %w[read])
    grant(@hans, "KnowledgeItem", %w[read])
    @docs = 3.times.map do |i|
      Document.create!(kind: :brief, subject: "Brief #{i + 1}", status: :entwurf)
    end
    login_as(@hans)
  end

  def uuids
    page.evaluate_script(<<~JS)
      Array.from(document.querySelectorAll("#blade_stack_container .stack-card"))
           .map(c => c.dataset.uuid)
    JS
  end

  # Capybara nimmt Modifier als POSITIONSARGUMENTE (`click(:alt)`).
  def zeile_klicken(doc, modifier: [])
    zeile = find("#document_row_#{doc.id}", match: :first, wait: 10)
    modifier.empty? ? zeile.click : zeile.click(*modifier)
  end

  def per_menue_oeffnen(doc, art)
    zeile_klicken(doc, modifier: [:shift])
    assert_selector "#blade_open_menu", wait: 5
    find("#blade_open_menu button[data-open-art='#{art}']").click
  end

  def liste_oeffnen
    page.driver.resize_window(1600, 900)
    visit "/documents?stack=list:documents"
    assert_selector "#blade_stack_container .stack-card[data-uuid='list:documents']", wait: 10
  end

  def card(doc) = "document:#{doc.id}"

  def erste_card_oeffnen
    liste_oeffnen
    zeile_klicken(@docs[0])
    assert_selector ".stack-card[data-uuid='#{card(@docs[0])}']", wait: 10
  end

  test "schlichter Klick ersetzt alles rechts der Liste" do
    erste_card_oeffnen
    zeile_klicken(@docs[1])
    assert_selector ".stack-card[data-uuid='#{card(@docs[1])}']", wait: 10
    assert_no_selector ".stack-card[data-uuid='#{card(@docs[0])}']", wait: 5
    assert_equal ["list:documents", card(@docs[1])], uuids
  end

  test "Menü-Wahl „rechts“ öffnet rechts neben der Liste" do
    erste_card_oeffnen
    per_menue_oeffnen(@docs[1], "rechts")
    assert_selector ".stack-card[data-uuid='#{card(@docs[1])}']", wait: 10
    assert_equal ["list:documents", card(@docs[1]), card(@docs[0])], uuids
  end

  test "Menü-Wahl „am Ende“ hängt ans Stapel-Ende" do
    erste_card_oeffnen
    per_menue_oeffnen(@docs[1], "ende")
    assert_selector ".stack-card[data-uuid='#{card(@docs[1])}']", wait: 10
    assert_equal ["list:documents", card(@docs[0]), card(@docs[1])], uuids
  end

  test "Alt+Klick wirkt wie ein schlichter Klick" do
    erste_card_oeffnen
    zeile_klicken(@docs[1], modifier: [:alt])
    assert_no_selector "#blade_open_menu", wait: 3
    assert_selector ".stack-card[data-uuid='#{card(@docs[1])}']", wait: 10
    assert_equal ["list:documents", card(@docs[1])], uuids
  end

  test "Strg-Klick hängt nicht an" do
    erste_card_oeffnen
    vorher = uuids
    zeile_klicken(@docs[1], modifier: [:control])
    sleep 0.8
    assert_equal vorher, uuids, "Strg/Cmd gehoert dem Browser, nicht dem Stapel"
  end

  test "eine offene Card wird angesprungen, egal was gedrückt ist" do
    erste_card_oeffnen
    vorher = uuids
    zeile_klicken(@docs[0], modifier: [:alt])
    sleep 0.8
    assert_equal vorher, uuids, "keine zweite Karte desselben Dokuments"
  end

  test "Umschalt-Klick markiert keinen Text in der Zeile" do
    liste_oeffnen
    zeile_klicken(@docs[0], modifier: [:shift])
    assert_selector "#blade_open_menu", wait: 5
    assert_equal "", page.evaluate_script("window.getSelection().toString().trim()")
  end
end
