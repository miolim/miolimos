# #532 (Hans, 2026-06-08): ein festgeschriebener PDF-Stand eines Dokuments.
class DocumentArtifact < ApplicationRecord
  belongs_to :document
  belongs_to :creator, class_name: "Actor", optional: true

  scope :recent, -> { order(created_at: :desc) }
end
