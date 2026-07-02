class CreateWikilinkResearchJobs < ActiveRecord::Migration[8.1]
  def change
    create_table :wikilink_research_jobs do |t|
      t.string  :source_knowledge_item_id, null: false
      t.string  :target_title,             null: false
      t.string  :target_source_url
      t.bigint  :task_id,                  null: false
      t.string  :target_knowledge_item_id
      t.timestamps
    end

    add_index :wikilink_research_jobs, :source_knowledge_item_id
    add_index :wikilink_research_jobs, :task_id, unique: true
    add_index :wikilink_research_jobs,
              [:source_knowledge_item_id, :target_title],
              name: "idx_wikilink_jobs_source_title"

    add_foreign_key :wikilink_research_jobs, :knowledge_items,
                    column: :source_knowledge_item_id, primary_key: :uuid
    add_foreign_key :wikilink_research_jobs, :knowledge_items,
                    column: :target_knowledge_item_id, primary_key: :uuid
    add_foreign_key :wikilink_research_jobs, :tasks, column: :task_id
  end
end
