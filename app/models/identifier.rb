# #544 (Hans, 2026-06-08): eine ID-Nummer (Key-Value) am Person/Org-KI.
# `label` = Typ (Kundennummer/Steuernummer/…), `value` = Nummer. Optionale
# `counterparty` = die Gegenseite, die die Nummer vergibt (paarweise wie eine
# Kundennummer; ohne Gegenseite eigenständig wie eine Steuernummer).
# DB ist Source of Truth — keine Frontmatter-Synchronisation (#241).
class Identifier < ApplicationRecord
  belongs_to :knowledge_item, class_name: "KnowledgeItem",
             foreign_key: :knowledge_item_uuid, primary_key: :uuid
  belongs_to :counterparty, class_name: "KnowledgeItem",
             foreign_key: :counterparty_uuid, primary_key: :uuid, optional: true

  # #1094 (Hans, 2026-07-22): Vorschlagsliste der ID-Typen. Sie ist reine
  # Bequemlichkeit (das Label bleibt Freitext) — aber sie gehört an EINE
  # Stelle, damit der Editor und ContactEnrichment dieselben Typen kennen.
  TYPE_SUGGESTIONS = [
    "USt-IdNr", "Steuernummer", "Steuer-IdNr",
    "Registergericht", "Handelsregisternummer",
    "Gläubiger-Identifikationsnummer", "Kundennummer", "Vertragsnummer",
    "Versichertennummer", "Mitgliedsnummer", "Personalnummer", "ORCID", "IBAN"
  ].freeze

  validates :label, presence: true
  validates :value, presence: true

  scope :ordered, -> { order(:position, :id) }
end
