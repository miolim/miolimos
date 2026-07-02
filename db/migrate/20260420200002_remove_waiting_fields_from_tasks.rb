class RemoveWaitingFieldsFromTasks < ActiveRecord::Migration[8.1]
  def change
    remove_index  :tasks, :follow_up_at
    remove_column :tasks, :waiting_for,  :text
    remove_column :tasks, :follow_up_at, :date
  end
end
