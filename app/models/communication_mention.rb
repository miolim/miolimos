class CommunicationMention < ApplicationRecord
  belongs_to :communication
  belongs_to :mentioned,
    class_name: "KnowledgeItem",
    foreign_key: :mentioned_uuid, primary_key: :uuid

  ROLES = %w[sender recipient cc bcc].freeze

  validates :role, inclusion: { in: ROLES + [""] }
  validates :communication_id, uniqueness: { scope: [:mentioned_uuid, :role] }
end
