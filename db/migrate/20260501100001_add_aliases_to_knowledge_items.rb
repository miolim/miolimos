class AddAliasesToKnowledgeItems < ActiveRecord::Migration[8.1]
  def change
    add_column :knowledge_items, :aliases, :string, array: true, default: []
    add_index  :knowledge_items, :aliases, using: :gin
  end
end
