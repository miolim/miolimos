# #428 Phase 1 (Hans, 2026-05-31): Zentrale Tag-Entitaet mit Metadaten
# (Farbe/Beschreibung) + polymorphe taggings. Additiv: die bestehenden
# tasks.tags / knowledge_items.tags Array-Spalten bleiben vorerst die
# Zuordnungs-Quelle (taggings spiegeln sie), damit Filter/Suche/Frontmatter
# unangetastet bleiben. Task nutzt integer-id, KnowledgeItem uuid — daher
# zwei Zuordnungsspalten (Praezedenz: KnowledgeItem reply parent_id_int/
# parent_uuid).
class CreateTagsAndTaggings < ActiveRecord::Migration[8.1]
  def change
    create_table :tags do |t|
      t.string :name,        null: false
      t.string :color                       # z.B. "amber" / Hex — Rendering spaeter
      t.text   :description
      t.timestamps
    end
    add_index :tags, "lower(name)", unique: true, name: "index_tags_on_lower_name"

    create_table :taggings do |t|
      t.references :tag, null: false, foreign_key: true
      t.string  :taggable_type, null: false   # "Task" | "KnowledgeItem"
      t.bigint  :taggable_id_int               # Task#id
      t.string  :taggable_uuid                 # KnowledgeItem#uuid
      t.timestamps
    end
    add_index :taggings, [:tag_id, :taggable_type, :taggable_id_int],
      unique: true, name: "idx_taggings_unique_task", where: "taggable_id_int IS NOT NULL"
    add_index :taggings, [:tag_id, :taggable_type, :taggable_uuid],
      unique: true, name: "idx_taggings_unique_ki", where: "taggable_uuid IS NOT NULL"
    add_index :taggings, [:taggable_type, :taggable_id_int], name: "idx_taggings_task"
    add_index :taggings, [:taggable_type, :taggable_uuid], name: "idx_taggings_ki"
  end
end
