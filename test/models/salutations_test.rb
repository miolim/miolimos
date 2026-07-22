require "test_helper"

# #1090 (Hans): Ableitung der Briefanrede aus Geschlecht + Nachname, mit
# Freitext-Override am KI. Reine Modul-Logik — kein Dateisystem noetig.
class SalutationsTest < ActiveSupport::TestCase
  def person(**attrs)
    KnowledgeItem.new(item_type: :person, **attrs)
  end

  test "leitet aus Geschlecht + Nachname ab" do
    assert_equal "Sehr geehrte Frau Mustermann",
                 Salutations.line_for(person(gender: "female", last_name: "Mustermann"))
    assert_equal "Sehr geehrter Herr Muster",
                 Salutations.line_for(person(gender: "male", last_name: "Muster"))
  end

  test "divers gruesst mit vollem Namen statt zu raten" do
    assert_equal "Guten Tag Alex Kim",
                 Salutations.line_for(person(gender: "diverse", first_name: "Alex", last_name: "Kim"))
  end

  # #1090 Nachtrag (Hans): akademischer Titel als eigenes Feld.
  test "akademischer Titel steht zwischen Frau/Herr und Nachname" do
    assert_equal "Sehr geehrte Frau Prof. Dr. Meier",
                 Salutations.line_for(person(gender: "female", last_name: "Meier", academic_title: "Prof. Dr."))
    assert_equal "Sehr geehrter Herr Dr. Muster",
                 Salutations.line_for(person(gender: "male", last_name: "Muster", academic_title: "Dr."))
  end

  test "divers gruesst mit Titel + vollem Namen" do
    assert_equal "Guten Tag Dr. Alex Kim",
                 Salutations.line_for(person(gender: "diverse", first_name: "Alex", last_name: "Kim",
                                             academic_title: "Dr."))
  end

  test "Titel ohne Nachname bleibt neutral" do
    assert_equal Salutations::NEUTRAL,
                 Salutations.line_for(person(gender: "female", academic_title: "Dr."))
  end

  test "Freitext am KI schlaegt die Ableitung" do
    p = person(gender: "female", last_name: "Mustermann", salutation: "Liebe Erika")
    assert_equal "Liebe Erika", Salutations.line_for(p)
  end

  test "ohne Geschlecht, ohne Nachname, ohne Person und ohne KI bleibt es neutral" do
    assert_equal Salutations::NEUTRAL, Salutations.line_for(person(last_name: "Mustermann"))
    assert_equal Salutations::NEUTRAL, Salutations.line_for(person(gender: "female"))
    assert_equal Salutations::NEUTRAL, Salutations.line_for(KnowledgeItem.new(item_type: :organization))
    assert_equal Salutations::NEUTRAL, Salutations.line_for(nil)
  end

  test "Organisation nutzt ihren Freitext, wenn gesetzt" do
    org = KnowledgeItem.new(item_type: :organization, salutation: "Liebes Team")
    assert_equal "Liebes Team", Salutations.line_for(org)
  end

  test "valid_gender? akzeptiert nur den Katalog" do
    assert Salutations.valid_gender?("female")
    assert_not Salutations.valid_gender?("quatsch")
    assert_not Salutations.valid_gender?("")
    assert_not Salutations.valid_gender?(nil)
  end
end
