class CreateTaskContacts < ActiveRecord::Migration[8.1]
  def change
    create_table :task_contacts do |t|
      t.references :task, null: false, foreign_key: true
      t.references :contact, null: false, foreign_key: true

      t.timestamps
    end

    add_index :task_contacts, [:task_id, :contact_id], unique: true
  end
end
