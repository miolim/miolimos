class CreateTaskTemplates < ActiveRecord::Migration[8.1]
  def change
    create_table :task_templates do |t|
      t.string  :title,        null: false
      t.text    :description
      # Optionaler Default-Agent — wird beim Quickadd in einem Agent-Slot
      # bevorzugt vorgeschlagen. NULL = globale Vorlage, sichtbar fuer alle.
      t.bigint  :agent_actor_id
      t.timestamps
    end

    add_index :task_templates, :agent_actor_id
    add_index :task_templates, :title
    add_foreign_key :task_templates, :actors, column: :agent_actor_id, on_delete: :nullify
  end
end
