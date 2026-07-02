class CreateContacts < ActiveRecord::Migration[8.1]
  def change
    create_table :contacts do |t|
      t.string :type, null: false
      t.string :slug, null: false

      t.string :first_name
      t.string :last_name

      t.string :name

      t.string :email
      t.string :phone
      t.string :website

      t.references :organization, foreign_key: { to_table: :contacts }

      t.timestamps
    end

    add_index :contacts, :type
    add_index :contacts, :slug, unique: true
  end
end
