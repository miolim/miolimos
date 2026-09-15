require "test_helper"

# #1057: Rechtsform-Katalog für Organisationen.
# #1610 (Hans): „GmbH & Co. KG als Rechtsform für Organisationen ergänzen."
class LegalFormsTest < ActiveSupport::TestCase
  test "GmbH & Co. KG ist eine gültige Rechtsform" do
    assert LegalForms.valid?("gmbh_co_kg")
    assert_not LegalForms.valid?("gmbh & co. kg"), "gespeichert wird der Schlüssel, nicht die Anzeige"
  end

  test "jede Rechtsform hat eine Bezeichnung in allen Sprachen" do
    I18n.available_locales.each do |locale|
      LegalForms::OPTIONS.each do |option|
        key = "knowledge.legal_forms.#{option}"
        assert I18n.exists?(key, locale), "#{locale}: #{key} fehlt"
      end
    end
  end

  test "die Anzeige lautet GmbH & Co. KG" do
    assert_equal "GmbH & Co. KG", I18n.t("knowledge.legal_forms.gmbh_co_kg", locale: :de)
    assert_equal "GmbH & Co. KG", I18n.t("knowledge.legal_forms.gmbh_co_kg", locale: :en)
  end
end
