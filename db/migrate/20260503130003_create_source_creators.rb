class CreateSourceCreators < ActiveRecord::Migration[8.1]
  def change
    create_table :source_creators do |t|
      t.references :source, null: false, foreign_key: true
      # Person/Org-KI (FK über uuid, weil KIs uuid als PK haben).
      t.string  :knowledge_item_uuid, null: false
      t.string  :role,    null: false, default: "author"
      t.integer :position, null: false, default: 0
      t.timestamps
    end
    add_index :source_creators, :knowledge_item_uuid
    add_index :source_creators, [:source_id, :position]
  end
end
