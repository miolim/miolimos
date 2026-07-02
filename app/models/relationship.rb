class Relationship < ApplicationRecord
  belongs_to :from_person, class_name: "KnowledgeItem",
    foreign_key: :from_uuid, primary_key: :uuid
  belongs_to :to_person, class_name: "KnowledgeItem",
    foreign_key: :to_uuid, primary_key: :uuid

  validates :from_uuid, presence: true
  validates :to_uuid,   presence: true
  validates :kind,      presence: true

  scope :ordered, -> {
    order(Arel.sql("COALESCE(end_at, '9999-12-31') DESC, COALESCE(start_at, '0001-01-01') ASC, id ASC"))
  }
end
