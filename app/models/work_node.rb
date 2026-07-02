# #325 (Hans, 2026-05-24): Work-Tree-Knoten. Verbindet ein Topic mit
# einer KI in einer bestimmten Rolle und Tree-Position. Inhalt lebt in
# der KI, NICHT am Node — der Node ist nur Struktur + Rolle + Order.
#
# Rollen:
#   - `heading`: Beim Render-Walk wird der KI-Title als Ueberschrift
#     (Heading-Level = Tree-Tiefe) gerendert. Der KI-Body erscheint
#     als Einleitung unter der Ueberschrift, vor den Kindern.
#   - `content`: Beim Render-Walk wird der KI-Body als laufender Text
#     gerendert. Der Title taucht im Render nicht auf.
#
# Invarianten (vgl. #325-Spec):
#   - parent muss zum gleichen Topic gehoeren (sonst Cross-Tree-Ref).
#   - knowledge_item ist Material des Topics; Auto-Link bei Drop.
#   - Mehrfach-Vorkommen einer KI im gleichen Tree ist erlaubt.
#   - position ist eindeutig pro (topic_id, parent_id) und wird beim
#     Reorder neu durchnummeriert.
# #592: WorkNode ist seit der Verallgemeinerung der generische Knoten
# ALLER Topic-Bäume (TopicTree) — der Work-Tree ist der Sonderfall
# kind=work. Knoten in kind=purpose-Bäumen tragen zusätzlich:
#   - `junctor` (and|or): wie verfeinern die KINDER diesen Knoten —
#     UND = Zerlegung (alle nötig), ODER = Auswahl (eine genügt).
#   - `chosen`: IST-Markierung an einem ODER-Kind (der gelebte Ast).
class WorkNode < ApplicationRecord
  # #602 S1: Baum-Knoten erben die Sichtbarkeit ihres Topics.
  include VisibleVia
  visible_via topic_column: :topic_id, owner_columns: []

  belongs_to :topic
  belongs_to :tree, class_name: "TopicTree", optional: false, inverse_of: :nodes
  belongs_to :parent, class_name: "WorkNode", optional: true
  has_many :children, -> { order(:position) },
           class_name: "WorkNode", foreign_key: :parent_id, dependent: :destroy,
           inverse_of: :parent

  # KI-Referenz via uuid (KIs nutzen uuid als PK).
  belongs_to :knowledge_item,
             foreign_key: :knowledge_item_uuid, primary_key: :uuid,
             optional: false

  # #592: Abwärtskompatibilität — Direkterzeugung ohne tree landet im
  # Default-Work-Tree des Topics (Alt-Verhalten vor der Verallgemeinerung).
  before_validation { self.tree ||= topic&.default_work_tree }

  ROLES    = %w[heading content].freeze
  JUNCTORS = %w[and or].freeze
  validates :role, inclusion: { in: ROLES }
  validates :junctor, inclusion: { in: JUNCTORS }, allow_nil: true
  validates :position, numericality: { only_integer: true }

  validate :parent_belongs_to_same_tree

  scope :roots, -> { where(parent_id: nil).order(:position) }

  private

  def parent_belongs_to_same_tree
    return unless parent
    errors.add(:parent, "muss zum gleichen Topic gehoeren") if parent.topic_id != topic_id
    errors.add(:parent, "muss zum gleichen Baum gehoeren")  if parent.tree_id != tree_id
  end
end
