# #533 (Hans, 2026-06-07): Zeitbuchung. Ein „logischer Timer" mit Bezug
# (optionales Projekt-Topic + optionaler Inhalt Aufgabe/KI/Kommunikation) und
# Status running/paused/finished. Die tatsächliche Zeit steckt in SEGMENTEN
# (#2): jede laufende Strecke ein Start–Ende. Pause schließt das offene
# Segment, Fortsetzen öffnet ein neues — die exakte Einordnung bleibt erhalten.
# Regel (Hans): genau EINER läuft, beliebig viele pausiert.
class TimeEntry < ApplicationRecord
  # #602 S1: sichtbar = eigene Buchungen + Buchungen sichtbarer Topics.
  include VisibleVia
  visible_via topic_column: :topic_id, owner_columns: [:actor_id]

  belongs_to :actor
  belongs_to :topic, optional: true
  belongs_to :invoice_line, optional: true   # #541: auf welcher Rechnungsposition abgerechnet
  has_many :time_segments, dependent: :destroy

  SUBJECT_TYPES = %w[Task KnowledgeItem Communication].freeze
  STATUSES      = %w[running paused finished].freeze

  validates :started_at, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :subject_type, inclusion: { in: SUBJECT_TYPES }, allow_nil: true
  validate  :ended_at_after_started_at
  validate  :subject_ref_consistency
  validate  :single_running_timer_per_actor

  scope :running,   -> { where(status: "running") }
  scope :paused,    -> { where(status: "paused") }
  scope :finished,  -> { where(status: "finished") }
  scope :active,    -> { where(status: %w[running paused]) }  # auf der Leiste sichtbar
  scope :for_actor, ->(a) { where(actor_id: a.id) }
  scope :recent,    -> { order(started_at: :desc) }
  scope :for_topic, ->(topic) { where(topic_id: topic.id) }
  # #541: abrechenbare, abgeschlossene Zeiten, die noch auf keiner Rechnung stehen.
  scope :invoiceable, -> { where(billable: true, status: "finished", invoice_line_id: nil) }
  scope :for_subject, ->(subject) {
    type = subject.class.base_class.name
    if subject.is_a?(KnowledgeItem)
      where(subject_type: type, subject_uuid: subject.uuid)
    else
      where(subject_type: type, subject_id_int: subject.id)
    end
  }

  def running?  = status == "running"
  def paused?   = status == "paused"
  def finished? = status == "finished"

  # Dauer = Summe aller Segmente (offenes Segment: bis jetzt).
  def duration_minutes
    (time_segments.to_a.sum(&:duration_seconds) / 60).floor
  end

  # #541: Stunden (für Rechnungspositionen) + Beschriftung der Buchung.
  def hours = (duration_minutes / 60.0).round(2)
  def bill_label
    note.presence || subject&.try(:title) || subject&.try(:name) || "Zeitaufwand"
  end

  # Für die Live-Uhr: bereits abgeschlossene Sekunden + Start der offenen
  # Strecke. So tickt die Anzeige korrekt über Pausen hinweg (kein Mitzählen
  # der Pausenlücken).
  def accumulated_seconds
    time_segments.to_a.select(&:ended_at).sum(&:duration_seconds)
  end

  def open_segment_started_at
    time_segments.to_a.find { |s| s.ended_at.nil? }&.started_at
  end

  # ── Übergänge ────────────────────────────────────────────────────
  # Startet einen NEUEN Timer und PAUSIERT einen evtl. laufenden (nicht stoppen).
  def self.start_timer!(actor:, topic: nil, subject: nil, note: nil, billable: false)
    transaction do
      pause_running_for(actor)
      now = Time.current
      entry = new(actor: actor, topic: topic, note: note, billable: billable,
                  status: "running", started_at: now)
      entry.assign_subject(subject)
      entry.save!
      entry.time_segments.create!(started_at: now)
      entry
    end
  end

  # Trägt eine fertige Buchung nach (Datum + Dauer) — ein geschlossenes Segment.
  def self.log_manual!(actor:, started_at:, minutes:, topic: nil, subject: nil,
                       note: nil, billable: false)
    transaction do
      finish = started_at + minutes.to_i.minutes
      entry = new(actor: actor, topic: topic, note: note, billable: billable,
                  status: "finished", started_at: started_at, ended_at: finish)
      entry.assign_subject(subject)
      entry.save!
      entry.time_segments.create!(started_at: started_at, ended_at: finish)
      entry
    end
  end

  # #5: Buchungen nach einem Schlüssel gruppieren; je Gruppe Summe + letzte
  # Buchung. Sortiert nach letzter Buchung absteigend (Hans-Spec).
  def self.consolidate(entries, &key)
    entries.group_by(&key).map { |k, list|
      { key: k, count: list.size, total: list.sum(&:duration_minutes),
        last: list.map(&:started_at).compact.max }
    }.sort_by { |g| g[:last] || Time.zone.at(0) }.reverse
  end

  def self.pause_running_for(actor)
    running.for_actor(actor).each { |e| e.pause!(reason: "superseded") }
  end

  def pause!(reason: "paused")
    return self unless running?
    transaction do
      close_open_segments!(Time.current, reason: reason)
      update!(status: "paused")
    end
    self
  end

  # Fortsetzen: pausiert zuerst einen evtl. anderen laufenden Timer.
  def resume!
    return self if running? || finished?
    transaction do
      self.class.pause_running_for(actor)
      update!(status: "running")
      time_segments.create!(started_at: Time.current)
    end
    self
  end

  # Hartes Beenden (Stop-Knopf) — schließt das offene Segment endgültig.
  def finish!(at: Time.current)
    return self if finished?
    transaction do
      close_open_segments!(at, reason: "finished")
      update!(status: "finished", ended_at: at)
    end
    self
  end

  # #3/#4: Zeiten anpassen. minutes (allein) → die Buchung auf EIN Segment
  # dieser Dauer setzen (ab bisherigem/angegebenem Start). Sonst überspannen
  # started_at/ended_at die Buchung (erstes Segment-Start / letztes Segment-Ende).
  def adjust_times!(started_at: nil, ended_at: nil, minutes: nil)
    transaction do
      if minutes
        base = started_at || self.started_at || Time.current
        time_segments.destroy_all
        time_segments.create!(started_at: base, ended_at: base + minutes.minutes,
                              end_reason: finished? ? "finished" : nil)
        update!(started_at: base, ended_at: (finished? ? base + minutes.minutes : ended_at))
      else
        segs = time_segments.order(:started_at, :id).to_a
        if started_at && segs.first
          segs.first.update!(started_at: started_at)
          update!(started_at: started_at)
        end
        if ended_at && segs.last
          segs.last.update!(ended_at: ended_at)
          update!(ended_at: ended_at) if finished?
        end
      end
    end
    self
  end

  SEGMENT_END_LABELS = {
    "paused"     => "Bearbeitung pausiert",
    "superseded" => "Andere Aufgabe begonnen",
    "finished"   => "Bearbeitung beendet"
  }.freeze

  # #2: chronologisches Ereignis-Log aus den Segmenten — für die Detailansicht.
  def events
    out = []
    time_segments.to_a.sort_by { |s| [s.started_at, s.id] }.each_with_index do |s, i|
      out << { at: s.started_at, action: "start",
               label: i.zero? ? "Bearbeitung gestartet" : "Bearbeitung fortgesetzt" }
      if s.ended_at
        out << { at: s.ended_at, action: "stop",
                 label: SEGMENT_END_LABELS[s.end_reason] || "Bearbeitung beendet" }
      end
    end
    out
  end

  # ── Inhaltsbezug ─────────────────────────────────────────────────
  def assign_subject(subject)
    return if subject.nil?
    self.subject_type = subject.class.base_class.name
    if subject.is_a?(KnowledgeItem)
      self.subject_uuid   = subject.uuid
      self.subject_id_int = nil
    else
      self.subject_id_int = subject.id
      self.subject_uuid   = nil
    end
  end

  def subject
    case subject_type
    when "KnowledgeItem" then KnowledgeItem.find_by(uuid: subject_uuid)
    when "Task"          then Task.find_by(id: subject_id_int)
    when "Communication" then Communication.find_by(id: subject_id_int)
    end
  end

  private

  def close_open_segments!(at = Time.current, reason: nil)
    time_segments.where(ended_at: nil).find_each { |s| s.update!(ended_at: at, end_reason: reason) }
  end

  def ended_at_after_started_at
    return if ended_at.blank? || started_at.blank?
    errors.add(:ended_at, "muss nach dem Start liegen") if ended_at < started_at
  end

  def single_running_timer_per_actor
    return unless running? && actor_id
    others = TimeEntry.running.where(actor_id: actor_id)
    others = others.where.not(id: id) if persisted?
    errors.add(:base, "Es läuft bereits ein Timer für diesen Actor") if others.exists?
  end

  def subject_ref_consistency
    return if subject_type.nil?
    if subject_type == "KnowledgeItem"
      errors.add(:subject_uuid, "fehlt") if subject_uuid.blank?
    else
      errors.add(:subject_id_int, "fehlt") if subject_id_int.blank?
    end
  end
end
