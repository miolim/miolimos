class CommunicationTopic < ApplicationRecord
  belongs_to :communication
  belongs_to :topic

  validates :communication_id, uniqueness: { scope: :topic_id }
end
