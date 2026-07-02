# #191: Persönlicher Pin eines KnowledgeItems durch einen Actor.
# Pin-Liste lebt auf /pinned (Sliding-Pane-Stack wie /knowledge_items).
class KnowledgeItemPin < ApplicationRecord
  belongs_to :actor
  belongs_to :knowledge_item,
             foreign_key: :knowledge_item_id,
             primary_key: :uuid

  validates :actor_id, uniqueness: { scope: :knowledge_item_id }

  scope :for_actor, ->(actor) { where(actor_id: actor.id) }
  scope :recent,    -> { order(pinned_at: :desc) }

  before_validation :default_pinned_at

  private

  def default_pinned_at
    self.pinned_at ||= Time.current
  end
end
