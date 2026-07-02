# #705 (b) (Hans, 2026-06-15): PromptTemplates können HTML-Antworten
# produzieren — das erzeugte KI wird dann als render_mode=html angelegt und
# im Blade als sandboxed iframe gerendert. Default bleibt markdown.
class AddOutputFormatToPromptTemplates < ActiveRecord::Migration[8.1]
  def change
    add_column :prompt_templates, :output_format, :string, default: "markdown", null: false
  end
end
