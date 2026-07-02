class SimplifyTaskStatus < ActiveRecord::Migration[8.1]
  # Enum vorher: open=0, in_progress=1, waiting=2, done=3, cancelled=4
  # Enum nachher: open=0, done=1
  #
  # Mapping:
  #   done (3)       → done (1)
  #   in_progress(1) → open (0)
  #   waiting (2)    → open (0)
  #   cancelled (4)  → open (0)  (kein Datenverlust; User kann löschen)

  def up
    execute "UPDATE tasks SET status = 99 WHERE status = 1"  # in_progress -> Zwischenwert
    execute "UPDATE tasks SET status = 1  WHERE status = 3"  # done (3) -> done (1)
    execute "UPDATE tasks SET status = 0  WHERE status IN (99, 2, 4)"  # rest -> open
  end

  def down
    # Nicht verlustfrei reversibel; hebe nur die Haupt-Mappings wieder an.
    execute "UPDATE tasks SET status = 3 WHERE status = 1"  # done (1) -> done (3)
  end
end
