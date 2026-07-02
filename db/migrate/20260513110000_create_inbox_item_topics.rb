# #171: Topics-Verknüpfung für InboxItems. Hans kann beim Anlegen schon
# das Thema setzen, der Processor vererbt es an die erzeugten KIs/Tasks.
class CreateInboxItemTopics < ActiveRecord::Migration[8.1]
  def change
    create_table :inbox_item_topics do |t|
      t.references :inbox_item, null: false, foreign_key: true
      t.references :topic,      null: false, foreign_key: true
      t.integer    :position,   null: false, default: 0
      t.timestamps
    end
    add_index :inbox_item_topics, [:inbox_item_id, :topic_id], unique: true
  end
end
