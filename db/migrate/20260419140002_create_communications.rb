class CreateCommunications < ActiveRecord::Migration[8.1]
  def change
    create_table :communications do |t|
      t.string :type, null: false, default: "Email"
      t.string :subject
      t.text :body
      t.datetime :sent_at
      t.integer :direction, null: false, default: 0
      t.string :external_id, null: false

      t.references :oauth_credential, foreign_key: true
      t.jsonb :raw_data, null: false, default: {}

      t.timestamps
    end

    add_index :communications, :external_id, unique: true
    add_index :communications, :type
    add_index :communications, :direction
    add_index :communications, :sent_at
  end
end
