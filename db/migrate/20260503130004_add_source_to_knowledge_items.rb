class AddSourceToKnowledgeItems < ActiveRecord::Migration[8.1]
  def change
    # `bib_source_id` — nicht `source_id` — weil knowledge_items.source
    # bereits ein Enum ist (claude/chatgpt/web/manual/…). Wir können die
    # Association nicht `source` nennen; `bib_source` macht klar, dass
    # es um die bibliographische Quelle geht.
    add_reference :knowledge_items, :bib_source, foreign_key: { to_table: :sources },
                                                  index: true, type: :bigint
    add_column    :knowledge_items, :locator_label, :string  # "page" | "Rn." | "§" | "section"
    add_column    :knowledge_items, :locator_value, :string  # "33" | "14" | "3 Abs. 2"
  end
end
