class AddCommunicationToTasks < ActiveRecord::Migration[8.1]
  def change
    add_reference :tasks, :communication, foreign_key: true
  end
end
