# Asana-style Auto-Promotion: Tasks ohne commitment springen anhand
# ihrer due_date in "soon" (≤ 7 Tage) bzw. "today" (≤ 1 Tag).
#
# Idempotent — wird vor jedem Render der /tasks-Liste und des Dashboards
# aufgerufen. Manuell gesetzte commitments werden nicht überschrieben
# (User-Wahl gewinnt). Kein Auto-Rollback: einmal "today" bleibt "today",
# auch wenn die due_date weiter weg geschoben wird.
module TaskAutoPromote
  module_function

  def run!(actor)
    return unless actor

    today = Date.current
    open  = Task.where(assignee_id: actor.id, status: Task.statuses[:open], commitment: nil)

    open.where("due_date <= ?", today + 1.day)
        .update_all(commitment: Task.commitments[:today])

    open.where("due_date <= ?", today + 7.days)
        .update_all(commitment: Task.commitments[:soon])
  end
end
