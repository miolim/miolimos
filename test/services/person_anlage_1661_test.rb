require "test_helper"

# #1677 (aus immoOS #1661 übernommen; Hans dort): „Können alle Stellen, wo Personen ausgewählt werden, so
# gebaut werden, dass dort auch neue Personen angelegt werden?"
#
# Die Namenszerlegung stand dreimal im Programm. Diese Tests halten fest, was
# die eine verbliebene Stelle tut.
class PersonAnlage1661Test < ActiveSupport::TestCase
  setup do
    @actor = create_human
    grant(@actor, "KnowledgeItem", %w[read create update])
    Current.actor = @actor
  end

  test "#1661: aus einem Namen wird eine Person mit Vor- und Nachnamen" do
    person = PersonKiResolver.aus_text!("Anna Bergmann", item_type: :person, actor: @actor)
    assert_equal "person", person.item_type
    assert_equal "Anna Bergmann", person.title
    assert_equal "Anna", person.first_name
    assert_equal "Bergmann", person.last_name
  end

  # Mehrteilige Vornamen gehören zum Vornamen — der Nachname ist das letzte Wort.
  test "#1661: mehrteilige Namen werden am letzten Wort getrennt" do
    person = PersonKiResolver.aus_text!("Anna Maria von Bergmann", item_type: :person, actor: @actor)
    assert_equal "Anna Maria von", person.first_name
    assert_equal "Bergmann", person.last_name
  end

  test "#1661: ein einzelnes Wort ist der Nachname" do
    person = PersonKiResolver.aus_text!("Bergmann", item_type: :person, actor: @actor)
    assert_nil person.first_name
    assert_equal "Bergmann", person.last_name
  end

  # Eine Organisation hat keinen Nachnamen — „Stadtwerke Eutin GmbH" würde
  # sonst unter „GmbH" einsortiert (so geschehen in der Personenliste, #1656).
  test "#1661: eine Organisation bekommt keine Namensteile" do
    org = PersonKiResolver.aus_text!("Stadtwerke Eutin GmbH", item_type: :organization, actor: @actor)
    assert_equal "organization", org.item_type
    assert_equal "Stadtwerke Eutin GmbH", org.title
    assert_nil org.first_name
    assert_nil org.last_name
  end

  test "#1661: leerer Text legt nichts an" do
    assert_nil PersonKiResolver.aus_text!("   ", item_type: :person, actor: @actor)
  end

  test "#1661: unbekannte Art wird als Person behandelt, nicht als Fehler" do
    person = PersonKiResolver.aus_text!("Anna Bergmann", item_type: "unfug", actor: @actor)
    assert_equal "person", person.item_type
  end
end
