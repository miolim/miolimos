# Der Bulk-Trigger (#155) legt EINEN Task an, an dem MEHRERE Wikilink-
# Recherche-Jobs hängen — `task_id` darf also nicht unique sein. Statt-
# dessen sichern wir die fachliche Eindeutigkeit über (source, title).
class FixWikilinkResearchJobsIndexes < ActiveRecord::Migration[8.1]
  def change
    remove_index :wikilink_research_jobs, :task_id
    add_index    :wikilink_research_jobs, :task_id

    remove_index :wikilink_research_jobs, name: "idx_wikilink_jobs_source_title"
    add_index    :wikilink_research_jobs,
                 [:source_knowledge_item_id, :target_title],
                 unique: true,
                 name: "idx_wikilink_jobs_source_title_unique"
  end
end
