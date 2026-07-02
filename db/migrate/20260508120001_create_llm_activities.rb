class CreateLlmActivities < ActiveRecord::Migration[8.1]
  def change
    create_table :llm_activities do |t|
      # Welche Art von LLM-Operation: paragraph_research,
      # inbox_ai_transform, inbox_youtube_whisper,
      # inbox_youtube_structure, inbox_youtube_summary, …
      t.string  :kind,        null: false
      t.string  :status,      null: false, default: "queued"
      t.bigint  :actor_id,    null: false
      t.string  :model
      t.string  :prompt_template_slug

      # Auslöser: knowledge_item:<uuid>#<anchor>, inbox_item:<id>, …
      t.string  :source_kind
      t.string  :source_id
      # Ergebnis: meist eine erzeugte KI
      t.string  :result_kind
      t.string  :result_id

      # Truncated Texte für die UI; vollen Output hält das Result-Objekt.
      t.text    :input_summary
      t.text    :output_summary
      t.text    :error_message

      t.integer :input_tokens
      t.integer :output_tokens
      t.decimal :cost_eur, precision: 8, scale: 4

      t.datetime :started_at
      t.datetime :completed_at

      t.timestamps
    end

    add_index :llm_activities, :status
    add_index :llm_activities, :kind
    add_index :llm_activities, :actor_id
    add_index :llm_activities, :created_at
    add_foreign_key :llm_activities, :actors, column: :actor_id
  end
end
