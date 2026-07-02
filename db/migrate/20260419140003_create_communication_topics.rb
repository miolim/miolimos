class CreateCommunicationTopics < ActiveRecord::Migration[8.1]
  def change
    create_table :communication_topics do |t|
      t.references :communication, null: false, foreign_key: true
      t.references :topic, null: false, foreign_key: true

      t.timestamps
    end

    add_index :communication_topics, [:communication_id, :topic_id], unique: true, name: "index_ct_on_comm_and_topic"
  end
end
