class CreateKnowledgeItemReferences < ActiveRecord::Migration[8.1]
  def change
    create_table :knowledge_item_references do |t|
      t.string :source_uuid, null: false
      t.string :target_uuid
      t.string :target_title, null: false
      t.integer :anchor_type, null: false, default: 0
      t.string :anchor_text

      t.timestamps
    end

    add_foreign_key :knowledge_item_references, :knowledge_items,
      column: :source_uuid, primary_key: :uuid, on_delete: :cascade
    add_foreign_key :knowledge_item_references, :knowledge_items,
      column: :target_uuid, primary_key: :uuid, on_delete: :nullify

    add_index :knowledge_item_references, :source_uuid
    add_index :knowledge_item_references, :target_uuid
    add_index :knowledge_item_references, :target_title
  end
end
