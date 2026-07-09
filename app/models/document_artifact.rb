# #532 (Hans, 2026-06-08): ein festgeschriebener PDF-Stand. Seit #926 die
# EINE gemeinsame Artefakt-Schicht aller druckbaren Entitäten (Anschreiben,
# Rechnung, …) — Nummern, Signatur, Portal-Freigabe laufen hier zusammen.
class DocumentArtifact < ApplicationRecord
  belongs_to :printable, polymorphic: true
  belongs_to :creator, class_name: "Actor", optional: true

  scope :recent, -> { order(created_at: :desc) }
end
