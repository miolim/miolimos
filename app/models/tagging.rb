# #428 (Hans, 2026-05-31): Verknuepfung Tag <-> getaggte Entitaet.
# Polymorph ueber zwei Spalten, weil Task eine integer-id und
# KnowledgeItem eine uuid als PK hat.
class Tagging < ApplicationRecord
  belongs_to :tag

  # #695: Communication (integer-id wie Task) ergänzt.
  validates :taggable_type, presence: true, inclusion: { in: %w[Task KnowledgeItem Communication] }

  scope :for_task, ->(task) { where(taggable_type: "Task", taggable_id_int: task.id) }
  scope :for_ki,   ->(ki)   { where(taggable_type: "KnowledgeItem", taggable_uuid: ki.uuid) }

  def taggable
    case taggable_type
    when "Task"          then Task.find_by(id: taggable_id_int)
    when "KnowledgeItem" then KnowledgeItem.find_by(uuid: taggable_uuid)
    when "Communication" then Communication.find_by(id: taggable_id_int)
    end
  end
end
