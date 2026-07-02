# #460 (Hans, 2026-06-04): Supersession als erstklassiges Lebenszyklus-
# Feld am KI (Achse B der Versionierung — Ablösung durch ein neues KI),
# analog zu deleted_at. NICHT über das anker-gebundene Relation-Modell.
class AddSupersessionToKnowledgeItems < ActiveRecord::Migration[8.1]
  def change
    add_column :knowledge_items, :superseded_by_uuid, :string
    add_column :knowledge_items, :superseded_at, :datetime
    add_column :knowledge_items, :superseded_by_actor_id, :bigint

    add_index :knowledge_items, :superseded_by_uuid
  end
end
