require "application_system_test_case"

# #1644 (Hans): „Ich hätte gern oben zwei Optionsfelder: Person | Organisation
# … Dann abhängig von der Option: Vorname/Nachname, Geschlecht oder
# Organisationsname, Rechtsform."
#
# Geprüft wird das Umschalten im Browser: Die Felder der nicht gewählten Art
# sind versteckt UND deaktiviert — deaktivierte Felder schickt der Browser
# nicht mit, sonst landete ein leerer Personenname in der Organisation.
class QuickCreatePersonOrg1644Test < ApplicationSystemTestCase
  setup do
    @hans = create_human
    %w[KnowledgeItem Task].each { |rt| grant(@hans, rt, %w[read create update]) }
    login_as(@hans)
  end

  def slot_oeffnen
    visit "/tasks"
    assert_selector "[data-controller~='quick-create']", visible: :all, wait: 10
    page.execute_script(<<~JS)
      document.querySelector("[data-quick-create-target='slot'][data-slot='person']").classList.remove("hidden")
    JS
    assert_selector "[data-slot='person'] [data-controller='entity-type-switch']", wait: 5
  end

  def gruppe(typ) = "[data-slot='person'] [data-entity-type-switch-target='gruppe'][data-typ='#{typ}']"

  def feld_aus?(typ, name)
    page.evaluate_script(<<~JS)
      document.querySelector("#{gruppe(typ)} [name='#{name}']")?.disabled === true
    JS
  end

  test "Person ist vorgewählt; die Organisationsfelder sind aus" do
    slot_oeffnen

    assert_selector "#{gruppe('person')}", visible: true
    assert_no_selector "#{gruppe('organization')}", visible: true
    assert feld_aus?("organization", "legal_form"), "Rechtsform ist deaktiviert, solange Person gilt"
    assert_equal "person", page.evaluate_script(
      "document.querySelector(\"[data-slot='person'] [name='item_type']\").value"
    )
  end

  test "Umschalten auf Organisation zeigt Name und Rechtsform" do
    slot_oeffnen
    find("[data-slot='person'] button[data-entity-type-switch-typ-param='organization']").click

    assert_selector "#{gruppe('organization')}", visible: true
    assert_no_selector "#{gruppe('person')}", visible: true
    assert feld_aus?("person", "first_name"), "Vorname ist deaktiviert, wenn Organisation gilt"
    assert_equal "organization", page.evaluate_script(
      "document.querySelector(\"[data-slot='person'] [name='item_type']\").value"
    )
  end

  test "eine Organisation anlegen öffnet ihre Card" do
    slot_oeffnen
    find("[data-slot='person'] button[data-entity-type-switch-typ-param='organization']").click
    find("#{gruppe('organization')} [name='title']").set("Beispiel Bau")
    # #1672 hat den Absende-Knopf in den Bedienelemente-Katalog gezogen — seither
    # ein <button type="submit">, kein <input>. Der Test suchte weiter das input
    # und war seitdem rot (Systemtests laufen nicht im Deploy-Tor).
    find("[data-slot='person'] [type='submit']").click

    assert_selector ".stack-card", text: "Beispiel Bau", wait: 10
    org = KnowledgeItem.find_by(title: "Beispiel Bau")
    assert_equal "organization", org&.item_type
  end
end
