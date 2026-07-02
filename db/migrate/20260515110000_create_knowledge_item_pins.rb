# #191: Persönliche „📌 Gepinnt"-Liste pro Actor. WIP-Notizen werden
# explizit gepinnt und tauchen auf /pinned auf — gleicher Stack-Layout
# wie /knowledge_items.
class CreateKnowledgeItemPins < ActiveRecord::Migration[8.1]
  def change
    create_table :knowledge_item_pins do |t|
      t.bigint    :actor_id,             null: false
      t.string    :knowledge_item_id,    null: false
      t.timestamp :pinned_at,            null: false
      t.timestamps
    end

    add_index :knowledge_item_pins, [:actor_id, :knowledge_item_id],
              unique: true, name: "idx_pins_actor_ki_unique"
    add_index :knowledge_item_pins, [:actor_id, :pinned_at]

    add_foreign_key :knowledge_item_pins, :actors
    add_foreign_key :knowledge_item_pins, :knowledge_items,
                    column: :knowledge_item_id, primary_key: :uuid
  end
end
