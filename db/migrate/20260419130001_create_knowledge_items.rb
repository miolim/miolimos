class CreateKnowledgeItems < ActiveRecord::Migration[8.1]
  def change
    create_table :knowledge_items, id: false do |t|
      t.string :uuid, primary_key: true, null: false

      t.string :title, null: false
      t.integer :item_type, null: false, default: 0
      t.integer :source, null: false, default: 5

      t.string :source_url

      t.string :file_path, null: false
      t.string :content_hash, null: false

      t.datetime :file_created_at
      t.datetime :file_updated_at
      t.datetime :indexed_at

      t.timestamps
    end

    add_index :knowledge_items, :file_path, unique: true
    add_index :knowledge_items, :content_hash
    add_index :knowledge_items, :item_type
    add_index :knowledge_items, :source
    add_index :knowledge_items, :title
  end
end
