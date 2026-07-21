# #1090 (Hans): Geschlecht + Briefanrede an Personen-KIs. Bis hierher war
# die Anrede ausschliesslich ein Freitext-Override PRO DOKUMENT
# (`documents.salutation`) mit dem konservativen Default „Sehr geehrte
# Damen und Herren" — der Kommentar in Document#salutation_line hat die
# fehlenden Stammdaten seit #532 explizit als Luecke gefuehrt.
#
# Aufteilung wie beim Rechtsform-Katalog (#1057, LegalForms): Katalog +
# Ableitung als Modul, bewusst KEIN Patch am KnowledgeItem — die Spalten
# `gender`/`salutation` stellt ActiveRecord selbst bereit.
#
# `gender` ist fakultativ; leer heisst „keine Angabe" und faellt auf die
# neutrale Anrede zurueck. `salutation` schlaegt als Freitext IMMER die
# Ableitung (fuer „Liebe Anna", Titel wie „Frau Prof. Dr. Meier" oder
# Formen, die kein Katalog abbildet).
module Salutations
  GENDERS = %w[female male diverse].freeze

  # Neutrale Anrede — ohne Geschlecht, fuer Organisationen und als
  # Rueckfallebene, wenn der Nachname fehlt.
  NEUTRAL = "Sehr geehrte Damen und Herren"

  def self.valid_gender?(value) = GENDERS.include?(value.to_s)

  # Die Briefanrede fuer ein Stammdaten-KI (Person oder Organisation).
  # Reihenfolge: Freitext am KI → Ableitung aus Geschlecht + Nachname →
  # neutral. Liefert NIE nil, damit der Brief-Render immer eine Zeile hat.
  def self.line_for(ki)
    return NEUTRAL if ki.nil?
    return ki.salutation if ki.salutation.present?
    return NEUTRAL unless ki.respond_to?(:person?) && ki.person?

    name = ki.last_name.presence
    case ki.gender
    when "female" then name ? "Sehr geehrte Frau #{name}" : NEUTRAL
    when "male"   then name ? "Sehr geehrter Herr #{name}" : NEUTRAL
    # „divers"/„ohne Angabe" (§ 22 Abs. 3 PStG) kennt keine etablierte
    # geschlechtsgebundene Form — wir gruessen mit dem vollen Namen statt
    # zu raten. Wer es anders will, setzt den Freitext.
    when "diverse" then (ki.display_name.presence ? "Guten Tag #{ki.display_name}" : NEUTRAL)
    else NEUTRAL
    end
  end
end
