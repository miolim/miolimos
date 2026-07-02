# #518 (Hans, 2026-06-05): KI-Beiträge, die einen Agenten per @-Mention
# ansprechen und (noch) nicht von ihm beantwortet sind — damit der Agent
# eine Diskussion AN einem KI genauso in seiner Inbox findet wie eine
# Antwort an einer Aufgabe.
#
# #587 (Hans, 2026-06-10): nicht mehr nur Reply-KIs — auch @-Mentions im
# BODY normaler KIs (Notizen etc.) zählen. Hans hatte den Researcher in
# einer Notiz angesprochen, und die Mention war hier unsichtbar.
# {Un}beantwortet = keine spätere eigene Antwort im selben Thread nach
# dem Zeitpunkt der Mention (actor_mentions.created_at — robust auch bei
# nachträglich editierten Bodies). Thread = parent_uuid des Replies bzw.
# das KI selbst bei Body-Mentions.
class AgentMentions
  def self.pending_for(actor)
    rows = ActorMention.where(actor_id: actor.id).order(:created_at).to_a
    return [] if rows.empty?
    mention_at = rows.to_h { |r| [r.knowledge_item_uuid, r.created_at] }

    kis = KnowledgeItem.where(uuid: mention_at.keys)
                       .where.not(creator_id: actor.id)
                       .to_a
    # Replies erst ab Veröffentlichung; normale KIs (Notizen) haben kein
    # published_at-Konzept im selben Sinn und zählen direkt.
    kis.select! { |k| k.item_type != "reply" || k.published_at.present? }
    kis.sort_by! { |k| mention_at[k.uuid] }

    kis.reject do |m|
      thread_uuid = m.item_type == "reply" ? m.parent_uuid : m.uuid
      KnowledgeItem.where(parent_uuid: thread_uuid, item_type: "reply", creator_id: actor.id)
                   .where("knowledge_items.created_at > ?", mention_at[m.uuid])
                   .exists?
    end
  end

  def self.count_for(actor)
    pending_for(actor).size
  end
end
