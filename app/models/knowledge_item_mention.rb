class KnowledgeItemMention < ApplicationRecord
  belongs_to :knowledge_item,
    foreign_key: :knowledge_item_uuid, primary_key: :uuid
  belongs_to :mentioned,
    class_name: "KnowledgeItem",
    foreign_key: :mentioned_uuid, primary_key: :uuid

  validates :knowledge_item_uuid, uniqueness: { scope: :mentioned_uuid }
end
