class CreateTaskDependencies < ActiveRecord::Migration[8.1]
  def change
    create_table :task_dependencies do |t|
      t.references :predecessor, null: false, foreign_key: { to_table: :tasks }
      t.references :successor, null: false, foreign_key: { to_table: :tasks }
      t.integer :dependency_type, null: false, default: 0

      t.timestamps
    end

    add_index :task_dependencies, [:predecessor_id, :successor_id], unique: true
  end
end
