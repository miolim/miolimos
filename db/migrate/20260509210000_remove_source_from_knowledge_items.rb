class RemoveSourceFromKnowledgeItems < ActiveRecord::Migration[8.1]
  # `source`-Enum (claude/chatgpt/web/manual/import) wird ersatzlos
  # gestrichen: die einzige relevante Frage "ist eine Quelle hinterlegt?"
  # beantwortet `bib_source_id` bereits präzise. Frontmatter-`source:`-Keys
  # bleiben in alten MDs liegen; Indexer ignoriert sie.
  def up
    remove_column :knowledge_items, :source
  end

  def down
    add_column :knowledge_items, :source, :integer, default: 5, null: false
  end
end
