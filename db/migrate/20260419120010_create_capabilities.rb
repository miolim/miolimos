class CreateCapabilities < ActiveRecord::Migration[8.1]
  def change
    create_table :capabilities do |t|
      t.references :actor, foreign_key: true
      t.references :team, foreign_key: true
      t.string :resource_type, null: false
      t.jsonb :actions, null: false, default: []
      t.integer :effect, null: false, default: 0
      t.jsonb :scope, null: false, default: {}

      t.timestamps
    end

    add_check_constraint :capabilities,
      "(actor_id IS NOT NULL AND team_id IS NULL) OR (actor_id IS NULL AND team_id IS NOT NULL)",
      name: "capabilities_actor_xor_team"

    add_index :capabilities, [:actor_id, :resource_type, :effect],
      unique: true, where: "actor_id IS NOT NULL",
      name: "index_capabilities_on_actor_resource_effect"

    add_index :capabilities, [:team_id, :resource_type, :effect],
      unique: true, where: "team_id IS NOT NULL",
      name: "index_capabilities_on_team_resource_effect"

    add_index :capabilities, :resource_type
  end
end
