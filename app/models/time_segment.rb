# #533 #2 (Hans, 2026-06-07): Ein Arbeitsintervall eines Timers. Offenes
# Segment (ended_at NULL) = der Timer läuft gerade. Pause schließt das offene
# Segment, Fortsetzen öffnet ein neues. So bleibt die exakte Einordnung
# erhalten (man sieht die tatsächlichen Strecken inkl. Lücken).
class TimeSegment < ApplicationRecord
  belongs_to :time_entry

  scope :open,   -> { where(ended_at: nil) }
  scope :closed, -> { where.not(ended_at: nil) }

  def duration_seconds
    return 0 unless started_at
    finish = ended_at || Time.current
    [(finish - started_at).to_i, 0].max
  end
end
