# #532 (Hans, 2026-06-08): ein freies Key-Value-Feld einer druckbaren
# Entität (Anschreiben, Rechnung, …). Wird im Informationsblock
# (Datumsbereich) ausgegeben und speist den {{key}}-Merge (#926).
class DocumentField < ApplicationRecord
  belongs_to :fieldable, polymorphic: true
  validates :label, presence: true
  validates :value, presence: true
  scope :ordered, -> { order(:position, :id) }
end
