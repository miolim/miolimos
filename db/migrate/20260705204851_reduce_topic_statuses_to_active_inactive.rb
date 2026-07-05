# #817: Topic-Status auf aktiv/inaktiv reduziert. Die drei Nicht-aktiv-
# Status (paused=1, completed=2, archived=3) verhielten sich funktional
# identisch (überall nur active-Filter) — sie kollabieren zu inactive=1.
class ReduceTopicStatusesToActiveInactive < ActiveRecord::Migration[8.1]
  def up
    execute "UPDATE topics SET status = 1 WHERE status IN (2, 3)"
  end

  def down
    # Nicht verlustfrei umkehrbar (completed/archived sind kollabiert);
    # inactive bleibt als paused=1 lesbar.
    raise ActiveRecord::IrreversibleMigration
  end
end
