class CreateActors < ActiveRecord::Migration[8.1]
  def change
    create_table :actors do |t|
      t.string :type, null: false
      t.string :name, null: false
      t.string :email
      t.boolean :active, null: false, default: true

      t.string :api_token
      t.text :description

      t.timestamps
    end

    add_index :actors, :type
    add_index :actors, :api_token, unique: true, where: "api_token IS NOT NULL"
    add_index :actors, :email, where: "email IS NOT NULL"
  end
end
