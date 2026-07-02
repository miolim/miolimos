class AddProvenanceToKnowledgeItems < ActiveRecord::Migration[8.1]
  # #241 Plan B: Provenance-Audit-Daten (origin, source_url, kind, …)
  # wandern aus File-Frontmatter in eine eigene jsonb-Spalte. Vorher
  # schrieb processor_base.rb das via merge_frontmatter! ins File; nach
  # Plan B ist die DB Source of Truth und akzeptiert keine unmapped
  # Frontmatter-Felder mehr.
  def change
    add_column :knowledge_items, :provenance, :jsonb, default: {}, null: false
    add_index :knowledge_items, :provenance, using: :gin
  end
end
