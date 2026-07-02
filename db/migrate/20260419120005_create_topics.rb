class CreateTopics < ActiveRecord::Migration[8.1]
  def change
    create_table :topics do |t|
      t.string :name, null: false
      t.string :slug, null: false
      t.text :description
      t.integer :status, null: false, default: 0
      t.string :color
      t.boolean :template, null: false, default: false

      t.references :creator, null: false, foreign_key: { to_table: :actors }
      t.references :team, foreign_key: true

      t.timestamps
    end

    add_index :topics, :slug, unique: true
    add_index :topics, :status
    add_index :topics, :template
  end
end
