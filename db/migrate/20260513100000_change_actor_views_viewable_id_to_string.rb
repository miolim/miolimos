# #160 Phase 5: viewable_id muss auch UUIDs (KnowledgeItem) aufnehmen,
# nicht nur bigint-IDs (Task/Topic/Source/Awaiting). Konvertiere die
# Spalte auf varchar — Postgres macht die Bestandsdaten via cast mit.
# Polymorphe Indizes auf (viewable_type, viewable_id) bleiben intakt.
class ChangeActorViewsViewableIdToString < ActiveRecord::Migration[8.1]
  def up
    change_column :actor_views, :viewable_id, :string, using: 'viewable_id::text'
  end

  def down
    change_column :actor_views, :viewable_id, :bigint, using: 'viewable_id::bigint'
  end
end
