class CreateRelations < ActiveRecord::Migration[8.1]
  # #239 Phase A: typed Relations zwischen KIs/Tasks/Topics/Sources/...
  # polymorph an beiden Enden. anchor_id ist die `^abc123`-Inline-Id
  # aus dem Markdown-Wikilink, eindeutig pro source-Item (base36 6
  # Zeichen). Spalten-Set wie in #239 ausdiskutiert.
  def change
    create_table :relations do |t|
      t.string  :source_uuid,     null: false   # KI: uuid; Task/Topic etc: stringified id
      t.string  :source_type,     null: false   # polymorphic discriminator ("KnowledgeItem", "Task", "Topic", "Source")
      t.string  :target_uuid,     null: false
      t.string  :target_type,     null: false
      t.string  :anchor_id,       null: false   # ^abc123 (base36, 6)
      t.string  :label                          # frei
      t.text    :description                    # markdown, optional
      t.string  :direction,       null: false, default: "source_to_target" # source_to_target | undirected | bidirectional
      t.references :recognized_by, foreign_key: { to_table: :actors }, null: true
      t.string  :recognized_role                # author_source | author_target | third_party | agent
      t.string  :recognized_via                 # frei: "Lektuere", "LLM", ...
      t.datetime :recognized_at
      t.datetime :orphaned_at                  # nicht mehr im Body referenziert (Provenance bleibt)
      t.timestamps
    end

    # Pro source-Item ist anchor_id eindeutig
    add_index :relations, [:source_uuid, :anchor_id], unique: true
    # Polymorph-Indices
    add_index :relations, [:source_type, :source_uuid]
    add_index :relations, [:target_type, :target_uuid]
    add_index :relations, :orphaned_at, where: "orphaned_at IS NOT NULL"
  end
end
