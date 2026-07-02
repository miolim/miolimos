class AddWorkflowInstructionsToActors < ActiveRecord::Migration[8.1]
  # #152: Agent-spezifische Workflow-Anleitung — wird im Settings-UI
  # gepflegt und beim Setup ins Memory-File des jeweiligen Agents
  # geschrieben.
  def change
    add_column :actors, :workflow_instructions, :text
  end
end
