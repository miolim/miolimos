# #387 Phase A.3 (Hans, 2026-05-28): Lookup-Tabelle fuer
# Color-Highlight-Anker (8-Hex-IDs am `==color|text==^id`-Wrap).
# Befuellt via KnowledgeItem-Save-Hook. Erlaubt schnelles
# `[[^anchor]]`-Wikilink-Resolving zu (KI-UUID, Anker).
class CreateKnowledgeItemAnchors < ActiveRecord::Migration[8.1]
  def change
    create_table :knowledge_item_anchors do |t|
      t.string :anchor,                null: false
      t.string :knowledge_item_uuid,   null: false
      t.timestamps
    end
    add_index :knowledge_item_anchors, :anchor, unique: true
    add_index :knowledge_item_anchors, :knowledge_item_uuid
  end
end
