# #533 #2 (Hans, 2026-06-07): Pause + mehrere Timer. Ein Timer akkumuliert Zeit
# jetzt über SEGMENTE (Start–Ende je laufender Strecke) — so bleibt die exakte
# „wann wurde gearbeitet"-Einordnung trotz Pause erhalten. Status:
# running / paused / finished. Genau einer läuft, beliebig viele pausiert.
class AddPauseSegmentsToTimeEntries < ActiveRecord::Migration[8.1]
  def up
    add_column :time_entries, :status, :string, null: false, default: "running"
    add_index  :time_entries, [:actor_id, :status]

    create_table :time_segments do |t|
      t.references :time_entry, null: false, foreign_key: true
      t.datetime :started_at, null: false
      t.datetime :ended_at
      t.timestamps
    end
    add_index :time_segments, [:time_entry_id, :ended_at]

    # Backfill: bestehende Einträge in genau ein Segment überführen und den
    # Status aus ended_at ableiten (Anzeige + Dauer kommen künftig aus Segmenten).
    execute <<~SQL.squish
      INSERT INTO time_segments (time_entry_id, started_at, ended_at, created_at, updated_at)
      SELECT id, started_at, ended_at, NOW(), NOW() FROM time_entries
    SQL
    execute <<~SQL.squish
      UPDATE time_entries SET status = CASE WHEN ended_at IS NULL THEN 'running' ELSE 'finished' END
    SQL
  end

  def down
    drop_table :time_segments
    remove_column :time_entries, :status
  end
end
