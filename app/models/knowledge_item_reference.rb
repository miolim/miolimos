class KnowledgeItemReference < ApplicationRecord
  belongs_to :source, class_name: "KnowledgeItem",
    foreign_key: :source_uuid, primary_key: :uuid
  belongs_to :target, class_name: "KnowledgeItem",
    foreign_key: :target_uuid, primary_key: :uuid, optional: true
  # #953: Aufgaben-Referenz [[#id]] — Ziel ist eine Task statt einer KI.
  belongs_to :target_task, class_name: "Task", optional: true

  enum :anchor_type, { file: 0, heading: 1, block: 2 }

  validates :source_uuid, presence: true
  validates :target_title, presence: true
end
