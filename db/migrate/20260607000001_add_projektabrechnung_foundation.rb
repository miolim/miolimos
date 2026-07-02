# #533 Phase 1 (Hans, 2026-06-07): Fundament für Projekt-/Zeiterfassung.
# - Topic wird (optional) zum Projekt: Kunde + Abrechenbarkeit.
# - Kunde = bestehende Person/Org-KI, erweitert um die einzige Rechnungs-
#   Stammdaten-Lücke (vat_id = USt-IdNr/Steuernr.), analog zu orcid.
# - Rechnungsadresse-Markierung am bestehenden ContactPoint.
# - time_entries: Zeitbuchungen (polymorpher Inhaltsbezug, ein laufender Timer).
class AddProjektabrechnungFoundation < ActiveRecord::Migration[8.1]
  def change
    add_column :topics, :customer_uuid, :string
    add_column :topics, :billable, :boolean, null: false, default: false
    add_index  :topics, :customer_uuid

    add_column :knowledge_items, :vat_id, :string

    add_column :contact_points, :billing, :boolean, null: false, default: false

    create_table :time_entries do |t|
      t.references :actor, null: false, foreign_key: true
      t.bigint   :topic_id          # Projekt-Anker (nullable: interne Zeit)
      t.string   :subject_type      # "Task" | "KnowledgeItem" | "Communication"
      t.bigint   :subject_id_int    # Task / Communication
      t.string   :subject_uuid      # KnowledgeItem
      t.datetime :started_at, null: false
      t.datetime :ended_at          # NULL = laufender Timer
      t.boolean  :billable, null: false, default: false
      t.text     :note
      t.timestamps
    end
    add_index :time_entries, :topic_id
    add_index :time_entries, [:actor_id, :ended_at]   # „laufender Timer je Actor"
    add_index :time_entries, [:subject_type, :subject_id_int]
    add_index :time_entries, [:subject_type, :subject_uuid]
    add_foreign_key :time_entries, :topics
  end
end
