class AddWaitingFieldsToTasks < ActiveRecord::Migration[8.1]
  def change
    add_column :tasks, :waiting_for,  :text
    add_column :tasks, :follow_up_at, :date

    add_index :tasks, :follow_up_at
  end
end
