require "application_system_test_case"

# #1677 (aus immoOS #1661/#1662 übernommen): der Personen-Picker im FORMULAR —
# hier im Beziehungs-Editor einer Person. Tippen filtert; findet die Suche
# niemanden, stehen unten „als Person anlegen" / „als Organisation anlegen".
# Angelegt wird erst beim Klick; die Kennung wandert ins versteckte Feld, die
# neue Card geht rechts auf. Der Controller ist NEU — der Test stellt auch
# sicher, dass er im Browser wirklich geladen wird (Manifest, importmap).
class PersonPicker1677Test < ApplicationSystemTestCase
  setup do
    @hans = create_human
    grant(@hans, "KnowledgeItem", %w[read create update delete])
    @anna = FileProxy.create(actor: @hans, title: "Anna Bergmann", item_type: :person, content: "")
    @max  = FileProxy.create(actor: @hans, title: "Max Meier", item_type: :person, content: "")
    login_as(@hans)
  end

  def editor_oeffnen
    page.driver.resize_window(1600, 900)
    visit "/knowledge_items?stack=#{@anna.uuid}"
    assert_selector ".stack-card[data-uuid='#{@anna.uuid}']", wait: 10
    # Der Schlüssel der Klapp-Merkung ist je Abschnitt eindeutig — „+" gibt es in
    # der Card sechsmal (Adresse, Bank, Kontaktdaten, IDs, Affiliations, Beziehungen).
    within("section[data-disclosure-storage-key-value='knowledge.#{@anna.uuid}.relations_edit']") do
      find("button[data-action*='rows-editor#add']").click
    end
    assert_selector "[data-controller='person-picker'] input[type='text']", wait: 5
  end

  def picker_feld = find("[data-controller='person-picker'] input[type='text']", match: :first)

  # Die Kennung steht als EIGENSCHAFT im versteckten Feld (nicht als Attribut) —
  # Capybara kann darauf nicht warten, also kurz selbst nachsehen.
  def kennung_im_feld(erwartet)
    wert = nil
    20.times do
      wert = page.evaluate_script("document.querySelector(\"[data-person-picker-target='uuid']\").value")
      break if wert == erwartet
      sleep 0.25
    end
    wert
  end

  test "tippen findet den vorhandenen Kontakt — die Wahl fuellt die Kennung" do
    editor_oeffnen
    picker_feld.send_keys("Max M")
    find("[data-person-picker-target='list'] li", text: "Max Meier", wait: 5).click

    assert_equal @max.uuid, kennung_im_feld(@max.uuid)
    assert_equal "Max Meier", picker_feld.value
  end

  test "findet die Suche niemanden, legt ein Klick die Person an und oeffnet ihre Card" do
    editor_oeffnen
    picker_feld.send_keys("Emma Roth")
    assert_selector "[data-person-picker-target='list'] li", text: I18n.t("kontakt_anlegen.person"), wait: 5
    assert_selector "[data-person-picker-target='list'] li", text: I18n.t("kontakt_anlegen.organisation")
    assert_nil KnowledgeItem.find_by(title: "Emma Roth"), "angelegt wird erst bei Bestätigung"

    find("[data-person-picker-target='list'] li", text: I18n.t("kontakt_anlegen.person")).click

    assert_selector ".stack-card", text: "Emma Roth", wait: 10
    emma = KnowledgeItem.find_by(title: "Emma Roth")
    assert_equal ["person", "Emma", "Roth"], [emma.item_type, emma.first_name, emma.last_name]
    assert_equal emma.uuid, kennung_im_feld(emma.uuid)
  end
end
