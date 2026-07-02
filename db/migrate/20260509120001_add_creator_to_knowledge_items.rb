class AddCreatorToKnowledgeItems < ActiveRecord::Migration[8.1]
  def change
    # Wer hat das KI angelegt. Optional, weil Bestands-KIs vor dieser
    # Migration keinen Creator haben — die werden durch einen Backfill
    # aus dem Git-Log nachgezogen, was nicht für jeden Datensatz
    # zuverlässig auflöst.
    add_reference :knowledge_items, :creator, foreign_key: { to_table: :actors },
                                                index: true, type: :bigint, null: true
  end
end
