class KnowledgeItemTopic < ApplicationRecord
  belongs_to :knowledge_item, foreign_key: :knowledge_item_uuid, primary_key: :uuid
  belongs_to :topic

  validates :knowledge_item_uuid, uniqueness: { scope: :topic_id }
end
