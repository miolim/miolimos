# #705 (Hans, 2026-06-15): KIs können ihren Body als HTML rendern (in einem
# sandboxed iframe) statt als Markdown — für reiche/interaktive Outputs.
# render_mode steuert die Darstellung; Default bleibt markdown.
class AddRenderModeToKnowledgeItems < ActiveRecord::Migration[8.1]
  def change
    add_column :knowledge_items, :render_mode, :string, default: "markdown", null: false
  end
end
