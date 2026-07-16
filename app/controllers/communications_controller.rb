class CommunicationsController < ApplicationController
  include KnowledgeStackHelpers

  before_action :set_communication, only: [:show, :destroy, :create_task, :create_awaiting,
                                           :accept_topic_suggestion, :reject_topic_suggestion, :card,
                                           :call_duration]

  # #163 Phase 5a-2: Listen-Blade fuer Cross-Entity-Stack.
  def list_card
    render partial: "communications/list_blade_card", layout: false
  end

  # #163 Phase 5b-1: Detail-Blade-Card-Fragment.
  def card
    render partial: "communications/blade_card", locals: { communication: @communication }, layout: false
  end

  def index
    scope = Communication.visible_to(current_actor)
    scope = scope.where(direction: params[:direction]) if params[:direction].present?
    if params[:topic_id].present?
      scope = scope.joins(:communication_topics).where(communication_topics: { topic_id: params[:topic_id] })
    end
    if (q = params[:q].to_s.strip).length >= 2
      like = "%#{q.downcase}%"
      scope = scope.where("LOWER(subject) LIKE :q OR LOWER(COALESCE(sender, '')) LIKE :q OR LOWER(COALESCE(body_excerpt, '')) LIKE :q", q: like)
    end

    # #87: Standardisierte Sort-Parameter. Default: sent_at desc.
    @sort = (params[:sort].presence || "sent_at").to_s
    @dir  = (params[:dir].presence  || "desc").to_s
    direction = @dir == "asc" ? :asc : :desc
    scope = case @sort
            when "sender"  then scope.order(Arel.sql("LOWER(COALESCE(sender, '')) #{direction}"), sent_at: :desc)
            when "subject" then scope.order(Arel.sql("LOWER(COALESCE(subject, '')) #{direction}"))
            else                scope.order(sent_at: direction)
            end

    # #221: Includes fuer Listenview — sender (via mentions), Topics,
    # OAuth-Credential werden alle pro Row gelesen.
    @communications = scope.includes(:topics, :oauth_credential,
                                     communication_mentions: :mentioned)
                           .limit(100)

    # Classifier-Status für den Button im Header.
    @unclassified_count   = Communication.visible_to(current_actor).left_joins(:communication_topics)
                                         .where(communication_topics: { id: nil }).count
    @classifier_available = Classifiers::OllamaEmbedder.new.available?

    # #163 Phase 6c: /communications ist eine Blade-Stack-Seite.
    if params[:stack].blank?
      params[:stack] = "list:communications"
    end
    @initial_stack_items  = build_initial_stack
    @initial_stack_bodies = bodies_for_initial_stack(@initial_stack_items)
  end

  # Batch-Klassifikation aller Mails ohne Topic-Zuordnung. Läuft
  # synchron — für Hans' Mail-Volumen schnell genug; die Flash-
  # Rückmeldung zeigt das Ergebnis.
  def classify_all
    embedder = Classifiers::OllamaEmbedder.new
    unless embedder.available?
      redirect_to communications_path,
        alert: "Klassifikator nicht erreichbar (Ollama läuft nicht). Setup in docs/ollama-setup.md."
      return
    end

    suggester = Classifiers::EmailTopicSuggester.new(embedder: embedder)
    stats = Hash.new(0)
    mails = Communication.visible_to(current_actor).left_joins(:communication_topics)
                         .where(communication_topics: { id: nil })

    mails.find_each do |mail|
      result = suggester.apply(mail)
      stats[result[:decision]] += 1
    end

    flash[:notice] = "Klassifikation fertig · auto=#{stats[:auto_assign]}  vorgeschlagen=#{stats[:suggest]}  übersprungen=#{stats[:skip]}"
    redirect_to communications_path
  end

  def show
    # Erster Aufruf markiert als gelesen (nur inbound — outbound braucht
    # kein read_at, das macht der unread?-Filter selbst).
    @communication.mark_read!
    # #163 Phase 6c: HTML-Vollaufruf von /communications/:id leitet auf
    # die Stack-Variante um — `/communications?stack=list:communications,
    # communication:<id>`.
    if !turbo_frame_request? && request.format.html?
      redirect_to communications_path(stack: "list:communications,communication:#{@communication.id}") and return
    end
  end

  # Hartes Löschen der lokalen Communication. Gmail bleibt unverändert
  # (Scope ist readonly). Task/Awaiting-Backlinks werden via
  # dependent: :nullify auf NULL gesetzt — Kontext bleibt erhalten.
  def destroy
    @communication.destroy!
    redirect_to communications_path, notice: "Aus miolimOS entfernt (in Gmail unverändert)"
  end

  # POST /communications/bulk_update
  # #1018 (Hans, 2026-07-16): Batch-Edit fuer Kommunikationslisten (analog
  # tasks#bulk_update). Erwartet ids[] (Pflicht) und entweder
  # mode=delete (hartes Loeschen wie #destroy — Gmail unveraendert) oder
  # add_topic_id (additive Themen-Zuordnung, bestehende bleiben).
  def bulk_update
    ids = Array(params[:ids]).map(&:to_i).uniq.reject(&:zero?)
    comms = Communication.visible_to(current_actor).where(id: ids)
                         .includes(:topics, :oauth_credential,
                                   communication_mentions: :mentioned)
    if comms.empty?
      render turbo_stream: helpers.toast_stream(message: t("shared.bulk.nothing_selected"))
      return
    end

    if params[:mode] == "delete"
      removed = comms.map(&:id)
      Communication.transaction { comms.each(&:destroy!) }
      streams = removed.map { |id| turbo_stream.remove("communication_row_#{id}") }
      streams << helpers.toast_stream(
        message: t("communications.bulk_deleted", count: removed.size))
      render turbo_stream: streams
    elsif (topic = Topic.find_by(id: params[:add_topic_id].presence&.to_i))
      Communication.transaction do
        comms.each { |c| CommunicationTopic.find_or_create_by!(communication: c, topic: topic) }
      end
      streams = comms.map do |c|
        turbo_stream.replace("communication_row_#{c.id}",
          partial: "communications/row",
          locals: { comm: c.reload, blade_kind: "communication", blade_id: c.id })
      end
      streams << helpers.toast_stream(
        message: t("communications.bulk_assigned", count: comms.size, topic: topic.name))
      render turbo_stream: streams
    else
      render turbo_stream: helpers.toast_stream(message: t("shared.bulk.no_action"))
    end
  end

  # Phase 6a — User übernimmt den Classifier-Vorschlag.
  def accept_topic_suggestion
    topic = @communication.suggested_topic
    if topic
      CommunicationTopic.find_or_create_by!(communication: @communication, topic: topic)
      @communication.update_columns(suggested_topic_decided_at: Time.current)
    end
    redirect_back fallback_location: communication_path(@communication)
  end

  # User lehnt den Vorschlag ab; nur decided_at setzen, kein Topic verknüpfen.
  def reject_topic_suggestion
    @communication.update_columns(suggested_topic_decided_at: Time.current)
    redirect_back fallback_location: communication_path(@communication)
  end

  # #765 (Hans): Anrufdauer nachträglich setzen/ändern — synchronisiert
  # Event-Endzeit und Zeitbuchung mit (siehe Call#apply_duration!).
  def call_duration
    @communication.apply_duration!(params[:duration_minutes], actor: current_actor) if @communication.is_a?(Call)
    redirect_back fallback_location: communication_path(@communication)
  end

  def create_task
    task = Task.create!(
      title:         params.fetch(:title, @communication.subject.presence || "Aufgabe aus E-Mail"),
      creator:       current_actor,
      assignee:      current_actor,
      communication: @communication
    )
    redirect_to task_path(task), notice: "Aufgabe angelegt"
  end

  # "Warte auf Antwort" aus der Kommunikations-Detailseite: erstellt einen
  # Awaiting, übernimmt Themen und Kontakt (Empfänger bei outbound,
  # Absender bei inbound).
  def create_awaiting
    subject   = @communication.subject.presence || "(ohne Betreff)"
    follow_up = (Date.parse(params[:follow_up_at]) rescue nil) || (Date.today + 7)
    contact_ki = primary_contact_ki_for(@communication)

    awaiting = Awaiting.new(
      creator:       current_actor,
      communication: @communication,
      contact_ki:    contact_ki,
      title:         params[:description].presence || params[:title].presence ||
                     "Antwort auf: #{subject}",
      follow_up_at:  follow_up
    )

    Awaiting.transaction do
      awaiting.save!
      @communication.topics.each do |topic|
        AwaitingTopic.find_or_create_by!(awaiting: awaiting, topic: topic)
      end
    end

    redirect_to awaiting_path(awaiting), notice: "Wartepunkt angelegt"
  rescue ActiveRecord::RecordInvalid => e
    redirect_to communication_path(@communication), alert: e.message
  end

  private

  def controller_action_to_capability
    return "create" if %w[create_task create_awaiting].include?(action_name)
    return "update" if %w[accept_topic_suggestion reject_topic_suggestion classify_all call_duration].include?(action_name)
    super
  end

  def controller_resource_type
    return "Task"     if action_name == "create_task"
    return "Awaiting" if action_name == "create_awaiting"
    super
  end

  def set_communication
    @communication = Communication.visible_to(current_actor).find(params[:id])
  end

  # Bei outbound: an wen die E-Mail ging (Empfänger). Bei inbound: wer
  # sie geschrieben hat (Absender). Erster Treffer reicht.
  def primary_contact_ki_for(comm)
    role = comm.outbound? ? "recipient" : "sender"
    comm.communication_mentions.where(role: role).first&.mentioned ||
      comm.communication_mentions.first&.mentioned
  end
end
