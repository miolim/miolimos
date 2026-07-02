class AwaitingTopic < ApplicationRecord
  belongs_to :awaiting
  belongs_to :topic

  validates :awaiting_id, uniqueness: { scope: :topic_id }
end
