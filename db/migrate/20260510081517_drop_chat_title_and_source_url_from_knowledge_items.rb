class DropChatTitleAndSourceUrlFromKnowledgeItems < ActiveRecord::Migration[8.1]
  # source_url und chat_title gehören konzeptionell zur Source, nicht
  # zum KI. Vor dieser Migration wurden alle KI-Daten via
  # KnowledgeSourceBackfill nach Source verlagert (bib_source-Verknüpfung
  # angelegt) und die Frontmatter-Keys per cleanup_frontmatter
  # entfernt. Diese Migration zieht das Schema nach.
  def up
    remove_column :knowledge_items, :source_url
    remove_column :knowledge_items, :chat_title
  end

  def down
    add_column :knowledge_items, :source_url, :string
    add_column :knowledge_items, :chat_title, :string
  end
end
