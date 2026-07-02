class CreateKnowledgeItemTopics < ActiveRecord::Migration[8.1]
  def change
    create_table :knowledge_item_topics do |t|
      t.string :knowledge_item_uuid, null: false
      t.references :topic, null: false, foreign_key: true

      t.timestamps
    end

    add_foreign_key :knowledge_item_topics, :knowledge_items,
      column: :knowledge_item_uuid, primary_key: :uuid

    add_index :knowledge_item_topics, :knowledge_item_uuid
    add_index :knowledge_item_topics, [:knowledge_item_uuid, :topic_id],
      unique: true, name: "index_kit_on_item_and_topic"
  end
end
