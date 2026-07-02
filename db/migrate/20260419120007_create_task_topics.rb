class CreateTaskTopics < ActiveRecord::Migration[8.1]
  def change
    create_table :task_topics do |t|
      t.references :task, null: false, foreign_key: true
      t.references :topic, null: false, foreign_key: true
      t.integer :position, null: false, default: 0

      t.timestamps
    end

    add_index :task_topics, [:task_id, :topic_id], unique: true
    add_index :task_topics, [:topic_id, :position]
  end
end
