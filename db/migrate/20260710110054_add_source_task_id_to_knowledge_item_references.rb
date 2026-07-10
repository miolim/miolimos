# #953 Folge (Hans): auch Task-BESCHREIBUNGEN sind Backlink-Quellen.
# Eine Referenz kommt jetzt entweder aus einem KI-Body (source_uuid)
# ODER aus einer Task-Beschreibung (source_task_id).
class AddSourceTaskIdToKnowledgeItemReferences < ActiveRecord::Migration[8.1]
  def change
    add_column :knowledge_item_references, :source_task_id, :bigint
    add_index  :knowledge_item_references, :source_task_id, where: "source_task_id IS NOT NULL"
    change_column_null :knowledge_item_references, :source_uuid, true
  end
end
