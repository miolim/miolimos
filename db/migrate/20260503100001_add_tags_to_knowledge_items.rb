class AddTagsToKnowledgeItems < ActiveRecord::Migration[8.1]
  def change
    add_column :knowledge_items, :tags, :string, array: true, default: []
    add_index  :knowledge_items, :tags, using: :gin
  end
end
