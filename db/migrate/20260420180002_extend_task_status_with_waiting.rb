class ExtendTaskStatusWithWaiting < ActiveRecord::Migration[8.1]
  # Bestehende Enum-Zuordnung: open: 0, done: 1
  # Neue Zuordnung:           open: 0, waiting: 1, done: 2
  # Das heißt: bestehende done-Tasks (1) müssen vor der Model-Änderung auf
  # status=2 umgeschrieben werden, damit Slot 1 für "waiting" frei wird.
  def up
    execute "UPDATE tasks SET status = 2 WHERE status = 1"
  end

  def down
    # Rollback: done (2) → 1, eventuelle waiting (1 alt = jetzt frei) → 0
    execute "UPDATE tasks SET status = 1 WHERE status = 2"
    execute "UPDATE tasks SET status = 0 WHERE status = 1"
  end
end
