class CreateCommunicationContacts < ActiveRecord::Migration[8.1]
  def change
    create_table :communication_contacts do |t|
      t.references :communication, null: false, foreign_key: true
      t.references :contact, null: false, foreign_key: true
      t.integer :role, null: false, default: 0

      t.timestamps
    end

    add_index :communication_contacts, [:communication_id, :contact_id, :role], unique: true, name: "index_cc_on_comm_contact_role"
  end
end
