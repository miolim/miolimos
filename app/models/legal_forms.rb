# #1057 (aus immoos #1031, Hans): Rechtsform-Katalog für Organisationen.
# Das Feld `knowledge_items.legal_form` ist fakultativ und reine Stammdaten-
# Auszeichnung; bewusst KEIN Patch am KnowledgeItem-Modell (das Spalten-
# Attribut stellt ActiveRecord automatisch bereit, die Logik liegt hier).
#
# `gdwe` (Gemeinschaft der Wohnungseigentümer, § 9a WEG) bleibt im Katalog,
# obwohl der Kern daran nichts ableitet: der immoos-Fork erkennt darüber
# WEG-Grundstücke (Property#weg) und baut mit dieser Übernahme seinen
# Stopgap ab.
module LegalForms
  OPTIONS = %w[gdwe gmbh ug ag gbr ohg kg eg ev einzelunternehmen sonstige].freeze

  def self.valid?(value) = OPTIONS.include?(value.to_s)

  # Ist die (KnowledgeItem-)Partei eine GdWE-Organisation?
  def self.gdwe?(ki) = ki&.organization? && ki.legal_form.to_s == "gdwe"
end
