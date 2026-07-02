# #516 (Hans, 2026-06-05): ORCID als Feld für Personen — starker Identifikator
# (priorisiert in der Entitäts-Recherche). Spalte wie first_name/last_name.
class AddOrcidToKnowledgeItems < ActiveRecord::Migration[8.1]
  def change
    add_column :knowledge_items, :orcid, :string
    add_index  :knowledge_items, :orcid, where: "orcid IS NOT NULL"
  end
end
