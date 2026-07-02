# #171: Join-Model zwischen InboxItem und Topic. Analog zu TaskTopic /
# KnowledgeItemTopic — der User pflegt schon beim Anlegen das Thema,
# der Processor vererbt es an die erzeugten Datensätze.
class InboxItemTopic < ApplicationRecord
  belongs_to :inbox_item
  belongs_to :topic

  validates :inbox_item_id, uniqueness: { scope: :topic_id }
end
