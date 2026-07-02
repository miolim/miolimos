class AddTargetBlockAnchorToRelations < ActiveRecord::Migration[8.1]
  # #312 follow-up (Hans, 2026-05-23): Vereinheitlichung — ein Wikilink
  # IST eine Relation. Block-Anker-Wikilinks bekommen jetzt ALLE eine
  # Relation, mit `target_block_anchor` = die Anker-Id im Target-Body.
  # Renderer scrollt beim Klick zum Absatz, wenn das Feld gesetzt ist.
  # Keine Doppelung mehr zwischen "bloßer Wikilink" und "typed Relation".
  def change
    add_column :relations, :target_block_anchor, :string
  end
end
