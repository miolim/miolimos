# #816: Stack-Verlauf geräteübergreifend — Server-Tabelle je Nutzer,
# localStorage wird zum Cache. dedup_key = finale Card-Komposition
# (gleiche Dedup-Semantik wie bisher clientseitig).
class CreateStackSnapshots < ActiveRecord::Migration[8.1]
  def change
    create_table :stack_snapshots do |t|
      t.references :actor, null: false, foreign_key: true
      t.string  :history_key, null: false
      t.string  :dedup_key,   null: false
      t.jsonb   :trail,       null: false, default: []
      t.integer :current,     null: false, default: 0
      t.boolean :pinned,      null: false, default: false
      t.datetime :saved_at,   null: false
      t.timestamps
    end
    add_index :stack_snapshots, [:actor_id, :history_key, :dedup_key],
              unique: true, name: "index_stack_snapshots_uniqueness"
    add_index :stack_snapshots, [:actor_id, :history_key, :saved_at]
  end
end
