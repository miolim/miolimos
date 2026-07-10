# #953: Aufgaben-Referenzen ([[#id]]) im Wikilink-Index erfassen, damit
# das Task-Detail eine Backlinks-Sektion zeigen kann. KI-Refs tragen
# weiterhin target_uuid; Task-Refs stattdessen target_task_id.
class AddTargetTaskIdToKnowledgeItemReferences < ActiveRecord::Migration[8.1]
  def change
    add_column :knowledge_item_references, :target_task_id, :bigint
    add_index  :knowledge_item_references, :target_task_id, where: "target_task_id IS NOT NULL"
  end
end
