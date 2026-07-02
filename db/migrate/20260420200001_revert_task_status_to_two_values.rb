# Rückbau Phase 5: Task.status war {open:0, waiting:1, done:2},
# jetzt wieder {open:0, done:1}. Wartepunkte bekommen in Teil 2 eine
# eigene Tabelle — hier räumen wir die Tasks-Tabelle auf.
class RevertTaskStatusToTwoValues < ActiveRecord::Migration[8.1]
  def up
    # Reihenfolge wichtig: erst done (2) → 1, dann waiting (1) → 0.
    # Wenn wir zuerst waiting → 0 machen, kollidieren später done (2→1)
    # und die neu-erzeugten open (die vorher waiting waren).
    execute "UPDATE tasks SET status = 1 WHERE status = 2"
    execute "UPDATE tasks SET status = 0 WHERE status = 1"
    # Alle noch-übrigen 2er (sollte keine geben) sicherheitshalber auf 0
    execute "UPDATE tasks SET status = 0 WHERE status = 2"
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "Waiting-Tasks sind jetzt Awaitings in eigener Tabelle."
  end
end
