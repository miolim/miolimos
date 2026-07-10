class KnowledgeItemReference < ApplicationRecord
  # #953 Folge: Quelle ist ein KI-Body ODER eine Task-Beschreibung —
  # genau eine von beiden.
  belongs_to :source, class_name: "KnowledgeItem",
    foreign_key: :source_uuid, primary_key: :uuid, optional: true
  belongs_to :source_task, class_name: "Task", optional: true
  belongs_to :target, class_name: "KnowledgeItem",
    foreign_key: :target_uuid, primary_key: :uuid, optional: true
  # #953: Aufgaben-Referenz [[#id]] — Ziel ist eine Task statt einer KI.
  belongs_to :target_task, class_name: "Task", optional: true

  enum :anchor_type, { file: 0, heading: 1, block: 2 }

  validates :target_title, presence: true
  validate  :exactly_one_source

  # Das Quell-Objekt unabhängig von der Herkunft (KI oder Task).
  def source_object = source || source_task

  private

  def exactly_one_source
    unless source_uuid.present? ^ source_task_id.present?
      errors.add(:base, "genau eine Quelle: source_uuid ODER source_task_id")
    end
  end
end
