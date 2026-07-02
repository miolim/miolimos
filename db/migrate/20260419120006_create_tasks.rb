class CreateTasks < ActiveRecord::Migration[8.1]
  def change
    create_table :tasks do |t|
      t.string :title, null: false
      t.text :description
      t.integer :status, null: false, default: 0
      t.integer :priority, null: false, default: 1
      t.date :due_date
      t.datetime :completed_at

      t.references :assignee, foreign_key: { to_table: :actors }
      t.references :creator, null: false, foreign_key: { to_table: :actors }
      t.references :parent, foreign_key: { to_table: :tasks }

      t.timestamps
    end

    add_index :tasks, :status
    add_index :tasks, :priority
    add_index :tasks, :due_date
  end
end
