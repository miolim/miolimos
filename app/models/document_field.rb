# #532 (Hans, 2026-06-08): ein freies Key-Value-Feld am Dokument. Wird im
# Informationsblock (Datumsbereich) ausgegeben.
class DocumentField < ApplicationRecord
  belongs_to :document
  validates :label, presence: true
  validates :value, presence: true
  scope :ordered, -> { order(:position, :id) }
end
