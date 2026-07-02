class CreateTaskSources < ActiveRecord::Migration[8.1]
  def change
    create_table :task_sources do |t|
      t.references :task,   null: false, foreign_key: true
      t.references :source, null: false, foreign_key: true
      t.timestamps
    end
    add_index :task_sources, [:task_id, :source_id], unique: true
  end
end
