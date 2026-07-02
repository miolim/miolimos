# #480 Increment 3 (Hans, 2026-06-03): Block-/Highlight-Anker, die in einer
# Task-Description stehen, indizieren — damit `[[^anker]]`-Wikilinks (Absatz-
# Link / Kommentar / Aufgabe an einer Stelle der Beschreibung) global auf den
# Task-Absatz aufloesen, genau wie KnowledgeItemAnchor das fuer KI-Bodies tut.
class CreateTaskAnchors < ActiveRecord::Migration[8.1]
  def change
    create_table :task_anchors do |t|
      t.references :task, null: false, foreign_key: true
      t.string :anchor, null: false
      t.timestamps
    end
    add_index :task_anchors, :anchor, unique: true
  end
end
