# #573: Ereignis/Termin — eine Entität, zwei Blickrichtungen: ein geplanter
# Termin wird durchs Stattfinden zur Dokumentation. Optional an ein Projekt
# (Topic) und an eine Communication (z.B. dokumentierter Anruf) gebunden.
class Event < ApplicationRecord
  # #602 S1: sichtbar = eigene Termine + Termine sichtbarer Topics.
  include VisibleVia
  visible_via topic_column: :topic_id

  belongs_to :topic, optional: true
  belongs_to :creator, class_name: "Actor", optional: true
  belongs_to :communication, optional: true

  # #573 v2: Push-Spiegel in den Google-Kalender (No-Op ohne Scope).
  after_create_commit  -> { GcalPush.upsert(self) }
  after_update_commit  -> { GcalPush.upsert(self) }
  after_destroy_commit -> { GcalPush.remove(gcal_event_id) }

  validates :title, presence: true
  validates :starts_at, presence: true
  validate  :ends_after_start

  scope :upcoming, -> { where(starts_at: Time.current..).order(:starts_at) }
  scope :past,     -> { where(starts_at: ...Time.current).order(starts_at: :desc) }
  scope :in_month, ->(date) { where(starts_at: date.beginning_of_month.beginning_of_day..date.end_of_month.end_of_day) }
  scope :for_portal, -> { where(portal_visible: true) }

  def past? = starts_at < Time.current

  private

  def ends_after_start
    return if ends_at.blank? || starts_at.blank? || ends_at >= starts_at
    errors.add(:ends_at, "muss nach dem Beginn liegen")
  end
end
