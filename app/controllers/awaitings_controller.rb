class AwaitingsController < ApplicationController
  include KnowledgeStackHelpers

  before_action :set_awaiting, only: [:show, :edit, :update, :destroy, :resolve, :create_task, :card]

  def index
    load_index_scope!
    # #163 Phase 6c: /awaitings ist eine Blade-Stack-Seite mit
    # `list:awaitings` als initialer Card.
    if params[:stack].blank?
      params[:stack] = "list:awaitings"
    end
    @initial_stack_items  = build_initial_stack
    @initial_stack_bodies = bodies_for_initial_stack(@initial_stack_items)
  end

  # #163 Phase 5a-2: Listen-Blade fuer Cross-Entity-Stack.
  def list_card
    render partial: "awaitings/list_blade_card", layout: false
  end

  # #163 Phase 5b-1: Detail-Blade-Card-Fragment.
  def card
    render partial: "awaitings/blade_card", locals: { awaiting: @awaiting }, layout: false
  end

  def show
    # #163 Phase 6c: HTML-Vollaufruf von /awaitings/:id leitet auf die
    # Stack-Variante um — `/awaitings?stack=list:awaitings,awaiting:<id>`.
    # Bookmarks bleiben teilbar (gleicher Deep-Link, nur indirekt),
    # turbo_frame-Loads (z.B. aus dem alten Master-Detail-Layout in
    # topics/show#waiting) rendern weiterhin das Detail-Partial.
    if !turbo_frame_request? && request.format.html?
      redirect_to awaitings_path(stack: "list:awaitings,awaiting:#{@awaiting.id}") and return
    end
  end

  def new
    @awaiting = Awaiting.new(
      follow_up_at:     Date.today + 7,
      task_id:          params[:task_id],
      communication_id: params[:communication_id],
      contact_uuid:     params[:contact_uuid]
    )
    # Vorauswahl des Themas, wenn aus einem Topic-Tab gekommen.
    if params[:topic_id].present?
      @awaiting.topics = Topic.where(id: params[:topic_id]).to_a
    end
  end

  def create
    attrs = awaiting_params
    # #739 (Hans): Quick-Add ohne Titel → Platzhalter statt Validierungsfehler,
    # Cursor danach ins (jetzt editierbare) Titelfeld.
    @blank_title = attrs[:title].blank?
    attrs[:title] = "Neuer Wartepunkt" if @blank_title
    # Quick-Add: nur ein Titel kommt, follow_up_at fehlt — default +7 Tage.
    attrs[:follow_up_at] = Date.today + 7 if attrs[:follow_up_at].blank?

    @awaiting = Awaiting.new(attrs.merge(creator: current_actor))
    topic = nil
    Awaiting.transaction do
      @awaiting.save!
      # Topic aus Quick-Add (topic_id, einzeln) oder Vollformular (topic_ids, Liste).
      if params[:topic_id].present?
        topic = Topic.find(params[:topic_id])
        AwaitingTopic.find_or_create_by!(awaiting: @awaiting, topic: topic)
      end
      sync_topics_by_ids(@awaiting, params.dig(:awaiting, :topic_ids))
    end

    # #301: Quick-Create aus der Topbar-Leiste — Wartepunkt-Card direkt
    # an den aktuellen Stack appenden. `blade_stack_container` existiert
    # nur auf Stack-Seiten; sonst ist der Stream ein No-Op.
    if params[:quick_create].present?
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.append("blade_stack_container",
            partial: "awaitings/blade_card", locals: { awaiting: @awaiting, focus_title: @blank_title })
        end
        format.html { redirect_to awaiting_path(@awaiting) }
      end
      return
    end

    # Quick-Add aus dem Topic-Tab: Liste anhängen, Form mit Autofokus
    # neu rendern, Detail-Pane mit dem neuen Wartepunkt füllen — User
    # bleibt auf der Topic-Seite und sieht den frisch angelegten Punkt
    # rechts im Detail.
    if topic
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: [
            turbo_stream.remove("awaitings_empty"),
            turbo_stream.append("awaitings_list",
              partial: "awaitings/row", locals: { awaiting: @awaiting }),
            turbo_stream.replace("awaiting_quickadd_form",
              partial: "awaitings/quickadd_form",
              locals: { topic: topic, autofocus: true }),
            # Fresh-create-Pfad: der `awaiting_<id>`-Div existiert noch
            # nicht — wir koennen nur das Legacy-Frame `awaiting_detail`
            # bedienen. Topic-Tab `?tab=waiting` ist heute noch split-
            # pane (kein Blade-Stack), das passt also dort.
            turbo_stream.replace("awaiting_detail",
              partial: "awaitings/detail",
              locals: { awaiting: @awaiting })
          ]
        end
        format.html { redirect_to topic_path(topic, tab: "waiting"), notice: "Wartepunkt angelegt" }
      end
      return
    end

    redirect_to awaiting_path(@awaiting), notice: "Wartepunkt angelegt"
  rescue ActiveRecord::RecordInvalid
    render :new, status: :unprocessable_entity
  end

  def edit
  end

  def update
    Awaiting.transaction do
      @awaiting.update!(awaiting_params)
      sync_topics_by_ids(@awaiting, params.dig(:awaiting, :topic_ids)) if params[:awaiting]&.key?(:topic_ids)
    end
    record_edit_view(@awaiting)
    redirect_to awaiting_path(@awaiting), notice: "Gespeichert"
  rescue ActiveRecord::RecordInvalid
    render :edit, status: :unprocessable_entity
  end

  def destroy
    id = @awaiting.id
    @awaiting.destroy!
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: detail_pane_reset_streams(id)
      end
      format.html { redirect_to(request.referer.presence || awaitings_path,
                                notice: "Wartepunkt gelöscht") }
    end
  end

  # Wartepunkt auflösen: Status auf resolved, optional mit resolution_note.
  # Turbo-Stream: Zeile aus der Liste entfernen + Detail-Frame leeren,
  # damit der gerade aufgelöste Punkt nicht weiter rechts hängt.
  def resolve
    @awaiting.resolve!(note: params[:resolution_note].presence)
    record_edit_view(@awaiting)
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: detail_pane_reset_streams(@awaiting.id)
      end
      format.html { redirect_to awaitings_path, notice: "Aufgelöst" }
    end
  end

  # Aus einem Wartepunkt wird eine konkrete Aufgabe.
  # Logik sitzt in AwaitingToTask.
  def create_task
    title = params[:title].presence || "Folgeaufgabe: #{@awaiting.title.truncate(40)}"
    new_task = AwaitingToTask.call(awaiting: @awaiting, creator: current_actor, title: title)
    redirect_to task_path(new_task), notice: "Aufgabe angelegt, Wartepunkt aufgelöst"
  rescue ActiveRecord::RecordInvalid => e
    redirect_to awaiting_path(@awaiting), alert: e.message
  end

  private

  def controller_action_to_capability
    return "update" if action_name == "resolve"
    return "create" if action_name == "create_task"
    super
  end

  # create_task erzeugt einen Task, nicht ein Awaiting.
  def controller_resource_type
    return "Task" if action_name == "create_task"
    super
  end

  def set_awaiting
    @awaiting = Awaiting.visible_to(current_actor).find(params[:id])
  end

  def load_index_scope!
    @show_resolved = ActiveModel::Type::Boolean.new.cast(params[:show_resolved])
    @overdue_only  = ActiveModel::Type::Boolean.new.cast(params[:overdue])
    @q             = params[:q].to_s.strip.presence

    scope = Awaiting.visible_to(current_actor).includes(:contact_ki, :topics, :creator)
    scope = @show_resolved ? scope.where(status: [:open, :resolved]) : scope.open
    scope = scope.where("follow_up_at < ?", Date.today) if @overdue_only
    if params[:topic_id].present?
      scope = scope.joins(:awaiting_topics).where(awaiting_topics: { topic_id: params[:topic_id] })
    end
    scope = scope.where(contact_uuid: params[:contact_uuid]) if params[:contact_uuid].present?
    if @q
      like = "%#{@q.downcase}%"
      scope = scope.where("LOWER(title) LIKE :q OR LOWER(COALESCE(description,'')) LIKE :q", q: like)
    end

    # #87: Standardisierte Sort-Parameter. Default „urgent" = bisheriges Verhalten.
    @sort = (params[:sort].presence || "urgent").to_s
    @dir  = (params[:dir].presence  || "asc").to_s
    direction = @dir == "desc" ? :desc : :asc
    scope = case @sort
            when "follow_up_at" then scope.order(Arel.sql("follow_up_at #{direction} NULLS LAST"))
            when "created_at"   then scope.order(created_at: direction)
            when "title"        then scope.order(Arel.sql("LOWER(title) #{direction}"))
            else                     scope.by_urgency
            end
    @awaitings = scope
  end

  def awaiting_params
    params.require(:awaiting).permit(:title, :description, :status, :follow_up_at,
                                     :resolved_at, :resolution_note,
                                     :contact_uuid, :communication_id, :task_id)
  end

  def sync_topics_by_ids(awaiting, ids)
    return if ids.nil?
    clean = Array(ids).map(&:to_i).reject(&:zero?)
    awaiting.topics = Topic.where(id: clean).to_a
  end

  # Streams für „aktuell selektierter Wartepunkt ist weg" — Row aus der
  # Liste raus + Detail-Frame mit Placeholder ersetzen + ggf. Blade-Card
  # aus dem Stack entfernen. Wird sowohl von destroy als auch resolve
  # genutzt; nicht-existierende Targets sind jeweils No-Ops.
  def detail_pane_reset_streams(awaiting_id)
    [
      turbo_stream.remove("awaiting_row_#{awaiting_id}"),
      turbo_stream.replace("awaiting_detail",
        helpers.turbo_frame_tag("awaiting_detail") do
          helpers.content_tag(:p, "Wartepunkt links auswählen →",
            class: "text-sm text-slate-400 italic")
        end),
      # #163: Blade-Pages: die Card aus dem Stack ziehen.
      turbo_stream.remove("stack_card_awaiting:#{awaiting_id}")
    ]
  end
end
