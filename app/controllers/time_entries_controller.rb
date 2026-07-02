# #533 (Hans, 2026-06-07): Zeitbuchungs-Endpoints. Eine Engine für
# Header-Timer, Card-Buttons und Quick-Add-Popup. #2: Pause/Fortsetzen +
# mehrere Timer (genau einer läuft, beliebig viele pausiert). JSON beschreibt
# den/die aktiven Timer, damit die Leiste konsistent „mitläuft".
class TimeEntriesController < ApplicationController
  include KnowledgeStackHelpers   # #5: build_initial_stack für die Stack-Seite
  skip_before_action :verify_authenticity_token,
    only: [:create, :stop, :pause, :resume, :finish, :reply_start, :reply_end, :reply_pause]
  before_action :set_entry, only: [:card, :update_times, :pause, :resume, :finish, :destroy, :set_billable]

  # GET /time_entries — Blade-Stack-Seite (#5). Default-Stack = list:time_entries
  # (die 3-Reiter-Zeiten-Liste); ?stack= hängt weitere Blades an.
  def index
    params[:stack] = "list:time_entries" if params[:stack].blank?
    @initial_stack_items  = build_initial_stack
    @initial_stack_bodies = bodies_for_initial_stack(@initial_stack_items)
  end

  # GET /time_entries/running — Zustand für die Leiste (laufender Timer +
  # alle aktiven inkl. pausierter).
  def running
    render json: running_state
  end

  # #557 (Hans, 2026-06-09): Standalone-Card des list:time_entries-Blades —
  # damit der Sidebar-Append (blade-stack holt /:resource/list_card) und der
  # Stack-Restore funktionieren. Vorher fehlte der Endpoint → Append lief in
  # 404 und fiel auf Voll-Navigation (neuer Stack) zurück.
  def list_card
    render partial: "time_entries/list_blade_card", layout: false
  end

  # #541 (Hans, 2026-06-09): eine Buchung nachträglich als abrechenbar
  # markieren (oder zurücknehmen). Bisher ließ sich „billable" nur beim
  # Timer-Start setzen — es fehlte ein Interface dafür.
  def set_billable
    @entry.update!(billable: ActiveModel::Type::Boolean.new.cast(params[:billable]))
    head :no_content
  end

  # POST /time_entries  (mode=timer | manual)
  def create
    topic    = params[:topic_id].present? ? Topic.find_by(id: params[:topic_id]) : nil
    subject  = resolve_subject
    note     = params[:note].to_s.strip.presence
    billable = ActiveModel::Type::Boolean.new.cast(params[:billable]) ? true : false

    if params[:mode].to_s == "manual"
      started = parse_time(params[:started_at]) || Time.current
      minutes = params[:minutes].to_i
      entry = TimeEntry.log_manual!(actor: current_actor, started_at: started,
                                    minutes: minutes, topic: topic, subject: subject,
                                    note: note, billable: billable)
    else
      entry = TimeEntry.start_timer!(actor: current_actor, topic: topic,
                                     subject: subject, note: note, billable: billable)
    end
    sync_subject_topic(subject, topic,
                       link:    ActiveModel::Type::Boolean.new.cast(params[:link_topic]),
                       replace: ActiveModel::Type::Boolean.new.cast(params[:replace_topics]))
    render json: running_state.merge(saved: serialize(entry))
  rescue => e
    render json: { error: e.message }, status: :unprocessable_content
  end

  # POST /time_entries/stop — beendet den aktuell laufenden Timer (Header-Stop).
  def stop
    entry = TimeEntry.running.for_actor(current_actor).first
    entry&.finish!
    render json: running_state.merge(stopped: entry ? serialize(entry) : nil)
  end

  # GET /time_entries/:id/card — Detail-Blade einer Buchung (Ereignis-Log).
  def card
    render partial: "time_entries/blade_card", locals: { entry: @entry }, layout: false
  end

  # PATCH /time_entries/:id/update_times — Start/Ende bzw. nur Dauer bearbeiten.
  # started_at + ended_at: überspannt die Buchung (erstes Segment-Start, letztes
  # Segment-Ende). minutes (allein): setzt die Buchung auf EIN Segment dieser
  # Dauer (Start bleibt). Nur für beendete/pausierte Buchungen sinnvoll.
  def update_times
    started = parse_time(params[:started_at])
    ended   = parse_time(params[:ended_at])
    minutes = params[:minutes].present? ? params[:minutes].to_i : nil
    @entry.adjust_times!(started_at: started, ended_at: ended, minutes: minutes)
    render json: running_state.merge(saved: serialize(@entry))
  rescue => e
    render json: { error: e.message }, status: :unprocessable_content
  end

  # POST /time_entries/:id/pause | resume | finish — je einzelner Timer.
  def pause
    @entry.pause!
    render json: running_state
  end

  def resume
    @entry.resume!
    render json: running_state
  end

  def finish
    @entry.finish!
    render json: running_state
  end

  # #533 #1: Auto-Timer beim Antwort-Bearbeiten. Start = Beginn der Bearbeitung
  # (Edit-Form auf / aktives Tippen). Regel (Hans): existiert für DIESE
  # Aufgabe/KI schon ein pausierter Timer, wird er nur FORTGESETZT (kein
  # neuer); läuft schon einer, passiert nichts; sonst neuer Timer.
  # #588 v2: Auto-Pausen finishen jetzt (eigene Buchung pro Strecke) —
  # der resume-Zweig greift nur noch für MANUELL pausierte Timer.
  def reply_start
    subject = resolve_subject
    if subject
      existing = active_for_subject(subject)
      if existing&.paused?
        existing.resume!
      elsif existing.nil?
        TimeEntry.start_timer!(actor: current_actor, subject: subject,
                               topic: default_topic_for(subject))
      end
    end
    render json: running_state
  end

  # #588 v2 (Hans, 2026-06-12): Fokus-Verlust am Edit-Feld (oder Blade) →
  # die Strecke wird als EIGENE Zeitbuchung abgeschlossen (finish statt
  # pause), damit bei automatisch erfassten Zeiten Start- und Endzeit
  # immer die Dauer ergeben. Wiederfokussieren startet via reply_start
  # eine NEUE Buchung. Mini-Strecken unter 30s verwerfen wir — sonst
  # müllt jede kurze Fokus-Berührung die Zeitenliste zu.
  def reply_pause
    subject = resolve_subject
    if subject && (entry = active_for_subject(subject)) && entry.running?
      entry.finish!
      entry.destroy if entry.time_segments.sum(&:duration_seconds) < 30
    end
    render json: running_state
  end

  # Ende der Bearbeitung (Entwurf/Senden) → der Timer dieser Aufgabe/KI wird
  # hart beendet (Hans-Entscheidung a).
  def reply_end
    subject = resolve_subject
    active_for_subject(subject)&.finish! if subject
    render json: running_state
  end

  # DELETE /time_entries/:id — Zeitbuchung löschen (Segmente kaskadieren).
  def destroy
    @entry.destroy
    render json: running_state
  end

  private

  def active_for_subject(subject)
    type = subject.class.base_class.name
    TimeEntry.active.for_actor(current_actor).to_a.detect do |e|
      next false unless e.subject_type == type
      subject.is_a?(KnowledgeItem) ? e.subject_uuid == subject.uuid : e.subject_id_int == subject.id
    end
  end

  # Bei genau einem Thema das Projekt vorbelegen, sonst keins (Auto-Timer soll
  # nicht blockieren / nachfragen).
  def default_topic_for(subject)
    topics = subject.respond_to?(:topics) ? subject.topics.to_a : []
    topics.size == 1 ? topics.first : nil
  end

  def set_entry
    @entry = TimeEntry.for_actor(current_actor).find(params[:id])
  end


  def running_state
    running = TimeEntry.running.for_actor(current_actor).first
    active  = TimeEntry.active.for_actor(current_actor).recent.to_a
    {
      running: running.present?,
      entry:   running ? serialize(running) : nil,    # Abwärtskompat. (ein Timer)
      active:  active.map { |e| serialize(e) }         # #2c: Leiste mit mehreren
    }
  end

  def serialize(e)
    {
      id:         e.id,
      status:     e.status,
      started_at: e.started_at&.iso8601,
      ended_at:   e.ended_at&.iso8601,
      running:    e.running?,
      paused:     e.paused?,
      minutes:    e.duration_minutes,
      accumulated_seconds: e.accumulated_seconds,
      running_since:       e.open_segment_started_at&.iso8601,
      note:       e.note,
      billable:   e.billable,
      topic:      e.topic && { id: e.topic.id, name: e.topic.name },
      subject:    subject_label(e)
    }
  end

  def subject_label(e)
    s = e.subject
    return nil unless s
    case e.subject_type
    when "Task"          then { type: "Task", id: s.id, label: s.title.to_s }
    when "KnowledgeItem" then { type: "KnowledgeItem", id: s.uuid, label: (s.display_label || s.title).to_s }
    when "Communication" then { type: "Communication", id: s.id, label: (s.try(:subject) || s.try(:title) || "Kommunikation").to_s }
    end
  end

  def sync_subject_topic(subject, topic, link:, replace:)
    return unless subject && topic
    join, key = case subject
                when Task          then [subject.task_topics, :topic_id]
                when KnowledgeItem then [subject.knowledge_item_topics, :topic_id]
                else return
                end
    if replace
      join.where.not(key => topic.id).destroy_all
      join.find_or_create_by!(topic: topic)
    elsif link
      join.find_or_create_by!(topic: topic)
    end
  end

  def resolve_subject
    case params[:subject_type]
    when "Task"          then Task.find_by(id: params[:subject_id])
    when "KnowledgeItem" then KnowledgeItem.find_by(uuid: params[:subject_id])
    when "Communication" then Communication.find_by(id: params[:subject_id])
    end
  end

  def parse_time(v)
    return nil if v.blank?
    Time.zone.parse(v.to_s)
  rescue ArgumentError
    nil
  end

  def controller_resource_type
    "Task"  # weicher Gate (V1), eigene Daten des Actors.
  end

  # Eigene Zeitbuchung löschen erfordert nur Task-„update" (nicht „delete") —
  # es sind die eigenen Daten, nicht die Aufgabe selbst.
  def controller_action_to_capability
    action_name == "destroy" ? "update" : super
  end
end
