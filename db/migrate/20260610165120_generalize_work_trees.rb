# #592: Der Work-Tree (#325) wird zum Sonderfall verallgemeinerter
# Topic-Bäume — dasselbe Knoten-Modell trägt künftig auch das
# Zweck-Mittel-Geflecht (kind=purpose) und erlaubt MEHRERE Bäume je
# Topic (Hans-Wunsch). Bestehende work_nodes wandern in je einen
# Default-Baum (kind=work, Name "Werk") ihres Topics.
class GeneralizeWorkTrees < ActiveRecord::Migration[8.1]
  def up
    create_table :topic_trees do |t|
      t.references :topic, null: false, foreign_key: true
      t.string  :kind, null: false, default: "work"
      t.string  :name
      t.integer :position, null: false, default: 1
      t.timestamps
    end

    add_reference :work_nodes, :tree, foreign_key: { to_table: :topic_trees }
    add_column :work_nodes, :junctor, :string                          # and|or (nur kind=purpose)
    add_column :work_nodes, :chosen,  :boolean, null: false, default: false  # IST-Markierung (ODER-Kind)

    execute <<~SQL
      INSERT INTO topic_trees (topic_id, kind, name, position, created_at, updated_at)
      SELECT DISTINCT topic_id, 'work', 'Werk', 1, NOW(), NOW() FROM work_nodes
    SQL
    execute <<~SQL
      UPDATE work_nodes wn SET tree_id = tt.id
      FROM topic_trees tt
      WHERE tt.topic_id = wn.topic_id AND tt.kind = 'work'
    SQL
    change_column_null :work_nodes, :tree_id, false
  end

  def down
    remove_column :work_nodes, :chosen
    remove_column :work_nodes, :junctor
    remove_reference :work_nodes, :tree
    drop_table :topic_trees
  end
end
