# #167: Soft-Publish-Pattern. Aufgaben und Kommentare können als
# Entwurf existieren — `published_at IS NULL`. Agent-Inbox sieht
# nur Veröffentlichte; Drafts bleiben für den Autor sichtbar.
#
# Bestehende Datensätze werden auf `published_at = created_at`
# zurückbeflossen — Verhalten unverändert für alles, was vor dem
# Feature angelegt wurde.
class AddPublishedAtToTasksAndComments < ActiveRecord::Migration[8.1]
  def up
    add_column :tasks,         :published_at, :datetime
    add_index  :tasks,         :published_at
    add_column :task_comments, :published_at, :datetime
    add_index  :task_comments, :published_at

    # Backfill — alles bisher Bestehende gilt als veröffentlicht.
    execute "UPDATE tasks SET published_at = created_at WHERE published_at IS NULL"
    execute "UPDATE task_comments SET published_at = created_at WHERE published_at IS NULL"
  end

  def down
    remove_index  :task_comments, :published_at
    remove_column :task_comments, :published_at
    remove_index  :tasks,         :published_at
    remove_column :tasks,         :published_at
  end
end
