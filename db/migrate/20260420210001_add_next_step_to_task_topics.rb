class AddNextStepToTaskTopics < ActiveRecord::Migration[8.1]
  def change
    add_column :task_topics, :next_step, :boolean, default: false, null: false

    # Pro Topic kann nur EINE Task next_step sein. Partial index, damit
    # die vielen next_step=false-Zeilen keinen Unique-Konflikt erzeugen.
    add_index :task_topics, :topic_id, unique: true,
      where: "next_step = true", name: "index_task_topics_on_topic_id_next_step"
  end
end
