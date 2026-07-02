# #155 Phase 5c: Verknuepfung Source ↔ (Recherche-)Topic mit
# Relevanz-Markierung. Aus [[Recherche durch Agenten]]: auch nicht-
# ergiebige und nicht-erreichte Quellen werden festgehalten, damit
# ablesbar bleibt, ob/inwieweit eine Quelle fuer die Synthese taugte.
class CreateSourceTopics < ActiveRecord::Migration[8.1]
  def change
    create_table :source_topics do |t|
      t.references :source, null: false, foreign_key: true
      t.references :topic,  null: false, foreign_key: true
      # relevant | irrelevant | unreached
      t.string :relevance, null: false, default: "relevant"
      t.text   :note
      t.timestamps
    end
    add_index :source_topics, [:source_id, :topic_id], unique: true
  end
end
