class BackfillTargetBlockAnchor < ActiveRecord::Migration[8.1]
  # #312 follow-up (Hans, 2026-05-23): bestehende Relations koennen
  # einen Block-Anker auf dem Target haben (= der User hatte einen
  # Copy-Wikilink-Absatzlink gemacht). RelationSync hatte das Feld
  # bisher nicht gefuehrt — wir scannen jetzt einmal alle Targets.
  def up
    return unless table_exists?(:relations)
    Relation.where(target_type: "KnowledgeItem")
            .where(target_block_anchor: nil)
            .find_each(batch_size: 200) do |rel|
      ki = KnowledgeItem.find_by(uuid: rel.target_uuid)
      next unless ki
      if ki.body.to_s.match?(/\^#{Regexp.escape(rel.anchor_id)}(?:\s|$)/)
        rel.update_column(:target_block_anchor, rel.anchor_id)
      end
    end
  end

  def down
    # no-op: das Feld kann sicher wieder leer sein.
  end
end
