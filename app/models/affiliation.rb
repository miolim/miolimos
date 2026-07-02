class Affiliation < ApplicationRecord
  belongs_to :person, class_name: "KnowledgeItem",
    foreign_key: :person_uuid, primary_key: :uuid
  belongs_to :organization, class_name: "KnowledgeItem",
    foreign_key: :organization_uuid, primary_key: :uuid

  validates :person_uuid,       presence: true
  validates :organization_uuid, presence: true

  # `primary` ist in Postgres ein reserviertes Wort und muss gequotet
  # werden — sonst Syntax-Error im ORDER-BY.
  scope :ordered, -> {
    order(Arel.sql(%q("primary" DESC, COALESCE(end_at, '9999-12-31') DESC, COALESCE(start_at, '0001-01-01') ASC, position ASC, id ASC)))
  }

  scope :active, -> { where(end_at: nil).or(where("end_at >= ?", Date.current)) }
end
