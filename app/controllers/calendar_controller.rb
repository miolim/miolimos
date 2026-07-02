# #573: der Kalender — v1 eine MISCH-ANSICHT über alle Zeitobjekte
# (Ereignisse/Termine, Meilensteine, Aufgaben-Fälligkeiten, Wartepunkte),
# global oder auf ein Projekt gefiltert. Plus Schnell-Erfassung für
# Termine und dokumentierte Anrufe (Call → Communication + Kalender-Event).
class CalendarController < ApplicationController
  include KnowledgeStackHelpers

  # Externer ICS-Feed authentifiziert über signierten Token (kein Login).
  skip_before_action :require_login,        only: :feed
  skip_before_action :enforce_access_gate,  only: :feed

  FEED_PURPOSE = "calendar_feed".freeze

  def index
    if params[:stack].blank?
      params[:stack] = "list:calendar"
    end
    @initial_stack_items  = build_initial_stack
    @initial_stack_bodies = bodies_for_initial_stack(@initial_stack_items)
  end

  def list_card
    render partial: "calendar/list_blade", layout: false
  end

  def create_event
    e = Event.new(event_params.merge(creator: current_actor))
    if e.save
      render_blade(month: e.starts_at.to_date)
    else
      render_blade(toast: e.errors.full_messages.to_sentence)
    end
  end

  # #573 v2: Termin bearbeiten/löschen (aus der Inline-Form im Blade).
  def update_event
    e = Event.visible_to(current_actor).find(params[:id])
    if e.update(event_params)
      render_blade(month: e.starts_at.to_date)
    else
      render_blade(toast: e.errors.full_messages.to_sentence)
    end
  end

  def destroy_event
    e = Event.visible_to(current_actor).find(params[:id])
    month = e.starts_at.to_date
    e.destroy!
    render_blade(month: month, toast: "Termin gelöscht.")
  end

  # Anruf dokumentieren: Communication (Call) + verknüpftes Kalender-Event.
  def create_call
    at    = parse_time(params[:at]) || Time.current
    wer   = params[:wer].to_s.strip
    notiz = params[:notiz].to_s.strip
    if wer.blank?
      render_blade(toast: "Bitte angeben, mit wem telefoniert wurde.") and return
    end
    call = Call.create!(
      direction: params[:direction] == "outbound" ? :outbound : :inbound,
      subject:   "Anruf: #{wer}", body: notiz.presence,
      sent_at:   at, external_id: "call-#{SecureRandom.uuid}"
    )
    # #598 (Hans): "Mit wem?" als Personen-KI verknüpfen — bestehende
    # Person/Org per Titel/Alias (CI), sonst Namens-Stub (wie beim
    # Quellen-Import, #516). Best-effort: scheitert die Verknüpfung
    # (z.B. fehlendes KI-Recht), bleibt der Anruf trotzdem erfasst.
    begin
      person = Authorship.find_or_create_person(wer, current_actor)
      CommunicationMention.create!(communication: call, mentioned_uuid: person.uuid) if person
    rescue StandardError => e
      Rails.logger.warn("create_call: Personen-Verknüpfung fehlgeschlagen: #{e.class} #{e.message}")
    end
    topic = params[:topic_id].present? ? Topic.find_by(id: params[:topic_id]) : nil
    CommunicationTopic.create!(communication: call, topic: topic) if topic
    Event.create!(title: "Anruf: #{wer}", starts_at: at, topic: topic,
                  creator: current_actor, communication: call,
                  description: notiz.presence)
    # #765 (Hans): Dauer → Event-Endzeit + Zeitbuchung (zählt bei den Zeiten
    # mit). Best-effort — scheitert das, bleibt der Anruf trotzdem erfasst.
    begin
      call.apply_duration!(params[:dauer], actor: current_actor)
    rescue StandardError => e
      Rails.logger.warn("create_call: Dauer/Zeitbuchung fehlgeschlagen: #{e.class} #{e.message}")
    end
    render_blade(month: at.to_date)
  end

  # #573 E3: ICS-Feed zum Abonnieren (Google/Apple/Outlook übernehmen die
  # Erinnerungen). Zugang über signierten, widerruflichen Token.
  # #602 S2: Feed je NUTZER — der Token trägt die actor_id, der Inhalt
  # läuft durch dessen Sichtbarkeits-Scope. Alte globale Tokens
  # ({scope:"all"}, vor S2) sind damit ungültig → Abo einmal neu
  # eintragen (mit Hans abgestimmt, #602).
  def feed
    data  = self.class.feed_verifier.verified(params[:token].to_s)
    # JSON-Serializer des Verifiers liefert String-Keys.
    actor_id = data.is_a?(Hash) ? (data["actor_id"] || data[:actor_id]) : nil
    actor = actor_id ? Actor.active.find_by(id: actor_id) : nil
    head :forbidden and return unless actor
    events     = Event.visible_to(actor).where(starts_at: 3.months.ago..)
    milestones = Task.visible_to(actor)
                     .where(client_milestone: true).where.not(published_at: nil).where.not(due_date: nil)
    render plain: IcsExport.calendar(events: events, milestones: milestones),
           content_type: "text/calendar"
  end

  def self.feed_verifier
    Rails.application.message_verifier(FEED_PURPOSE)
  end

  def self.feed_token(actor)
    feed_verifier.generate({ actor_id: actor.id })
  end

  private

  def render_blade(month: nil, toast: nil)
    streams = [ turbo_stream.replace("stack_card_list:calendar",
      partial: "calendar/list_blade", locals: { month_param: month&.strftime("%Y-%m-%d") }) ]
    streams << helpers.toast_stream(message: toast) if toast
    render turbo_stream: streams
  end

  def event_params
    p = params.require(:event).permit(:title, :starts_at, :ends_at, :location, :description, :topic_id, :portal_visible)
    p[:topic_id] = nil if p[:topic_id].blank?
    p
  end

  def parse_time(raw)
    Time.zone.parse(raw.to_s) rescue nil
  end

  def controller_resource_type = "Event"

  def controller_action_to_capability
    case action_name
    when "create_event", "create_call" then "create"
    when "update_event"  then "update"
    when "destroy_event" then "delete"
    else super
    end
  end
end
