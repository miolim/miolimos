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
  # #1610 (Hans): „GmbH & Co. KG als Rechtsform ergänzen" — steht bei den
  # KG-Formen, damit die Auswahl zusammenhängend bleibt.
  OPTIONS = %w[gdwe gmbh ug ag gbr ohg kg gmbh_co_kg eg ev einzelunternehmen sonstige].freeze

  def self.valid?(value) = OPTIONS.include?(value.to_s)

  # Ist die (KnowledgeItem-)Partei eine GdWE-Organisation?
  def self.gdwe?(ki) = ki&.organization? && ki.legal_form.to_s == "gdwe"
end
