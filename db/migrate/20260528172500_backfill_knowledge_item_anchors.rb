# #387 Phase A.3 (Hans, 2026-05-28): Bestandsdaten — KIs scannen, deren
# Body bereits `==color|text==^id`-Anker enthaelt (z.B. via
# Phase-A.1+A.2-Wraps), und in `knowledge_item_anchors` indexieren.
class BackfillKnowledgeItemAnchors < ActiveRecord::Migration[8.1]
  def up
    return unless ActiveRecord::Base.connection.table_exists?("knowledge_item_anchors")
    re = /==(?:[a-z]+)\|[^=]{1,800}?==\^([a-f0-9]{8})/m
    indexed = 0
    KnowledgeItem.where("body LIKE ?", "%==%==^%").find_each do |ki|
      anchors = ki.body.to_s.scan(re).flatten.uniq
      anchors.each do |a|
        KnowledgeItemAnchor.create!(knowledge_item_uuid: ki.uuid, anchor: a)
        indexed += 1
      rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
        # Anchor schon vergeben — Kollision (2 KIs nutzen dasselbe
        # 8-Hex zufaellig) oder Doppel-Eintrag. Beim Backfill
        # stillschweigend skippen; ein Cleanup-Job kann das spaeter
        # aufgreifen.
        next
      end
    end
    say "Backfilled #{indexed} anchors"
  end

  def down
    # destructive — wir loeschen alle Anchors. Phase-A.1+A.2-Wraps in
    # KI-Bodies bleiben unangetastet, nur die Lookup-Eintraege.
    KnowledgeItemAnchor.delete_all
  end
end
