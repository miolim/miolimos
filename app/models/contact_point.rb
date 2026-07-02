class ContactPoint < ApplicationRecord
  belongs_to :knowledge_item,
    foreign_key: :knowledge_item_uuid, primary_key: :uuid

  # #762 (Hans, 2026-06-23): kind "address" entfernt — Adressen werden
  # strukturiert als PostalAddress (#532) gepflegt, nicht mehr als
  # einzeiliger Kontaktpunkt. Bestand wurde nach PostalAddress migriert.
  KINDS = %w[email phone url fax im].freeze

  validates :kind,  inclusion: { in: KINDS }
  validates :value, presence: true

  scope :emails,    -> { where(kind: "email") }
  scope :phones,    -> { where(kind: "phone") }
  scope :urls,      -> { where(kind: "url") }
  # #533 Phase 1 (Hans, 2026-06-07): markiert die Rechnungsadresse eines
  # Kunden (Person/Org-KI). Kein neues Feld nötig — nur diese Markierung am
  # bestehenden Adress-ContactPoint.
  scope :billing,   -> { where(billing: true) }

  scope :ordered, -> { order(:position, :id) }
end
