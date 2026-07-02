class AddCommitmentToTasks < ActiveRecord::Migration[8.1]
  # Asana-style "Today / Soon / Later"-Sektionen für My Tasks.
  # nil = Eingang (noch nicht eingeordnet, Triage).
  # Auto-Promote füllt das Feld basierend auf due_date.
  def change
    add_column :tasks, :commitment, :integer
    add_index  :tasks, [:assignee_id, :commitment]
  end
end
