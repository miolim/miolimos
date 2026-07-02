# #592: Verallgemeinerte Topic-Bäume. Der Work-Tree (#325) ist seit #592
# ein Sonderfall (kind=work) desselben Knoten-Modells, das auch das
# Zweck-Mittel-Geflecht trägt (kind=purpose, Knoten mit junctor/chosen).
# Mehrere Bäume je Topic sind möglich (position ordnet sie).
class TopicTree < ApplicationRecord
  KINDS = %w[work purpose].freeze

  belongs_to :topic
  has_many :nodes, class_name: "WorkNode", foreign_key: :tree_id,
           dependent: :destroy, inverse_of: :tree

  validates :kind, inclusion: { in: KINDS }

  scope :work,    -> { where(kind: "work").order(:position) }
  scope :purpose, -> { where(kind: "purpose").order(:position) }

  def roots = nodes.where(parent_id: nil).order(:position)

  # #740 (Hans): Arten-Unterscheidung aufgehoben; ein unbenannter Baum
  # heißt schlicht „Baum" (vormals „Werk"/„Zweckgeflecht" je kind).
  def display_name = name.presence || "Baum"
end
