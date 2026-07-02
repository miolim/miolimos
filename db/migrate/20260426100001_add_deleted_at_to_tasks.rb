class AddDeletedAtToTasks < ActiveRecord::Migration[8.1]
  # Soft-Delete für Tasks. destroy setzt deleted_at = Time.current,
  # default-Scope schließt deleted aus. /trash zeigt sie für 30 Tage,
  # danach räumt ein Daily-Job hart auf.
  def change
    add_column :tasks, :deleted_at, :datetime
    add_index  :tasks, :deleted_at
  end
end
