# Reconciler für *_mentions-Joins (KnowledgeItemMention, TaskMention,
# CommunicationMention …): bringt die Menge der mentioned_uuid-Werte
# auf einer has_many-Association in Deckung mit `target_uuids`.
#
# Vorher dreimal als Inline-Schleife implementiert (TasksController,
# KnowledgeIndexer, …). Replacing-Semantik: was nicht in target_uuids
# steht, wird zerstört; was fehlt, wird angelegt. Selbst-Mentions
# werden über `exclude_self_uuid` rausgehalten (KI-zu-KI).
class MentionReconciler
  def self.reconcile!(association, target_uuids, exclude_self_uuid: nil)
    targets = Array(target_uuids).compact - [exclude_self_uuid].compact
    existing = association.pluck(:mentioned_uuid)
    (targets - existing).each { |uuid| association.create!(mentioned_uuid: uuid) }
    association.where.not(mentioned_uuid: targets).destroy_all
  end
end
