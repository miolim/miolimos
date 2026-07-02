class CreatePersonOrgRelations < ActiveRecord::Migration[8.1]
  def change
    create_table :affiliations do |t|
      t.string :person_uuid, null: false
      t.string :organization_uuid, null: false
      t.string :role, null: false, default: ""
      t.date   :start_at
      t.date   :end_at
      t.boolean :primary, null: false, default: false
      t.integer :position, null: false, default: 0
      t.timestamps
    end
    add_index :affiliations, :person_uuid
    add_index :affiliations, :organization_uuid
    add_index :affiliations, [:person_uuid, :organization_uuid, :role, :start_at],
              unique: true, name: "index_affiliations_unique_combo"

    create_table :relationships do |t|
      t.string :from_uuid, null: false
      t.string :to_uuid, null: false
      t.string :kind, null: false, default: ""
      t.date   :start_at
      t.date   :end_at
      t.timestamps
    end
    add_index :relationships, :from_uuid
    add_index :relationships, :to_uuid
    add_index :relationships, [:from_uuid, :to_uuid, :kind, :start_at],
              unique: true, name: "index_relationships_unique_combo"
  end
end
