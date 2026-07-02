class CreateWorkNodes < ActiveRecord::Migration[8.1]
  # #325 (Hans, 2026-05-24): Work-Tree-Konzept Phase 1.
  #
  # Ein Topic hat optional einen Work-Tree (= hierarchisierte, mit
  # Rollen versehene Teilmenge der KI-Materialen des Topics). Topics
  # ohne Work-Tree bleiben reine Themen-Sammlungen.
  #
  # Cascade-Verhalten (Stand: Hans bestaetigt):
  #   - topic_id           CASCADE  — Topic-Delete loescht den Tree.
  #   - knowledge_item_uuid RESTRICT — KI-Delete im Hard-Delete-Sinn
  #     wird blockiert, wenn die KI im Tree liegt. Soft-Delete (KI
  #     bekommt deleted_at) ist erlaubt; der Tree zeigt sie dann als
  #     verwaistes Material (Render-Pass behandelt das).
  #   - parent_id          CASCADE  — Sub-Tree-Delete kaskadiert.
  def change
    create_table :work_nodes do |t|
      t.references :topic, null: false, foreign_key: { on_delete: :cascade }
      t.string :knowledge_item_uuid, null: false
      t.references :parent, null: true, foreign_key: { to_table: :work_nodes, on_delete: :cascade }
      t.integer :position, null: false
      t.string  :role, null: false  # heading | content
      t.timestamps
    end

    # FK auf KI ueber uuid. RESTRICT: blockiert Hard-Delete.
    add_foreign_key :work_nodes, :knowledge_items,
                    column: :knowledge_item_uuid,
                    primary_key: :uuid,
                    on_delete: :restrict

    # Tree-Walk-Lookup.
    add_index :work_nodes, [:topic_id, :parent_id, :position]
    # "Wo wird diese KI verwendet?"
    add_index :work_nodes, :knowledge_item_uuid
    # Mehrfach-Vorkommen pro Topic erlaubt (Hans-Spec #5) — kein UNIQUE.
    add_index :work_nodes, [:topic_id, :knowledge_item_uuid, :role]
  end
end
