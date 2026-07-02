class AddDeletedAtToKnowledgeItems < ActiveRecord::Migration[8.1]
  # Soft-Delete für KnowledgeItems. destroy verschiebt die MD-Datei
  # zusätzlich in einen .trash/-Unterordner; Restore zieht sie zurück.
  # Nach 30 Tagen räumt ein Cron-Job hart auf.
  def change
    add_column :knowledge_items, :deleted_at, :datetime
    add_index  :knowledge_items, :deleted_at
  end
end
