class CreatePromptTemplates < ActiveRecord::Migration[8.1]
  def change
    create_table :prompt_templates do |t|
      t.string :name,        null: false
      t.string :slug,        null: false
      t.text   :description
      t.text   :prompt_text, null: false
      t.string :default_model            # z.B. "ollama:llama3.1:8b" oder "anthropic:claude-sonnet-4-6"
      t.references :creator, null: false, foreign_key: { to_table: :actors }
      t.timestamps
    end
    add_index :prompt_templates, :slug, unique: true
  end
end
