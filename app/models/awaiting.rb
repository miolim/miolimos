# Wartepunkt: "Ich warte auf etwas, das nicht in meinem Einflussbereich liegt."
# Eigenständige Entität — kein Task, kein STI. Hat keine Priority, keinen
# Assignee, keine Subtasks (das sind Task-Konzepte).
#
# Typischer Flow:
#   1. User legt Awaiting an (aus E-Mail, aus Task, oder frei)
#   2. follow_up_at gibt an, wann nachgefasst werden soll wenn nichts kommt
#   3. Entweder: resolve! (Antwort ist da, nichts weiter zu tun)
#       oder:    create_task aus Awaiting (braucht jetzt aktive Arbeit)
class Awaiting < ApplicationRecord
  # #602 S1: sichtbar = eigene Wartepunkte + solche an sichtbaren Topics.
  include VisibleVia
  visible_via join: "AwaitingTopic", join_fk: :awaiting_id

  belongs_to :creator, class_name: "Actor"
  # Person-KI, auf den/die wir warten (Nachfolger des alten Contacts).
  belongs_to :contact_ki, class_name: "KnowledgeItem",
    foreign_key: :contact_uuid, primary_key: :uuid, optional: true
  belongs_to :communication, optional: true
  belongs_to :task,          optional: true

  has_many :awaiting_topics, dependent: :destroy
  has_many :topics, through: :awaiting_topics

  enum :status, { open: 0, resolved: 1 }, default: :open

  validates :title,        presence: true
  validates :follow_up_at, presence: true

  scope :overdue,     -> { open.where("follow_up_at < ?", Date.today) }
  scope :due_soon,    -> { open.where(follow_up_at: Date.today..3.days.from_now) }
  scope :by_urgency,  -> { order(:follow_up_at) }
  scope :for_contact_ki, ->(ki) { where(contact_uuid: ki&.uuid) }

  def overdue?
    open? && follow_up_at && follow_up_at < Date.today
  end

  def days_waiting
    (Date.today - created_at.to_date).to_i
  end

  def resolve!(note: nil)
    update!(status: :resolved, resolved_at: Time.current, resolution_note: note)
  end
end
