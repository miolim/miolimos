class TopicsController < ApplicationController
  include TopicListLoading
  include KnowledgeStackHelpers

  before_action :set_topic, only: [:show, :edit, :update, :destroy, :instantiate,
                                   :reorder_tasks, :set_next_step, :clear_next_step,
                                   :detail_pane, :card, :list_card, :create_source,
                                   :render_preview, :render_card, :refs_card,
                                   :properties_card, :set_customer, :portal_preview,
                                   :calendar_tab]

  # #456 (Hans, 2026-06-02): /topics ist jetzt eine vollwertige Blade-
  # Stack-Seite (wie /tasks) mit der Themen-Liste als Starter — statt der
  # alten Baum-Verwaltungsansicht. Eigener Pfad = eigener Stack-Verlauf
  # (`topics.stack.history`) + eigener `stack.last`-Schluessel, sodass der
  # Wechsel zwischen Dashboard/Themen/Tags den jeweiligen Stack korrekt
  # wiederherstellt (vorher teilten sie sich /dashboard).
  def index
    params[:stack] = "list:topics" if params[:stack].blank?
    @initial_stack_items  = build_initial_stack
    @initial_stack_bodies = bodies_for_initial_stack(@initial_stack_items)
  end

  # JSON-Endpoint für die Slug-Autocomplete. Liefert bis zu 10 Topics,
  # gematcht gegen slug ODER name (case-insensitive substring).
  def suggest
    q = params[:q].to_s.strip.downcase
    scope = Topic.visible_to(current_actor).order(:name)
    scope = scope.where("LOWER(slug) LIKE :q OR LOWER(name) LIKE :q", q: "%#{q}%") if q.present?
    results = scope.limit(10).pluck(:slug, :name)
    render json: { items: results.map { |slug, name| { slug: slug, label: name } } }
  end

  # #196: Detail-Pane für die History-Page. Rendert nur das Topic-
  # Detail-Partial (das bereits in einem `topic_detail`-Frame liegt),
  # ohne den Rest der Show-Page.
  # #231: ohne Turbo-Frame-Request → Stack-Page-Redirect (Mobile-
  # Klick aus History-Liste). Sonst layoutlose Frame-Antwort. Topic
  # nimmt seinen eigenen Stack-Slug-Pfad (/topics/:slug) — der erlaubt
  # auch ?stack=list:history,topic:slug, aber TopicsController#show
  # macht das nicht standardmaessig. Stattdessen leiten wir auf
  # /knowledge_items?stack=list:history,topic:slug, damit auch hier
  # die erste Blade die Verlaufsliste ist.
  def detail_pane
    if !turbo_frame_request?
      redirect_to knowledge_items_path(stack: "list:history,topic:#{@topic.slug}") and return
    end
    render partial: "topics/detail", locals: { topic: @topic }, layout: false
  end

  # #163 Phase 4: Topic als Blade im Cross-Entity-Stack. Analog zu
  # tasks#card und sources#card — schlanke Glance-Card, Detail-Edits
  # ueber die Vollansicht.
  # #571 (Hans): das frühere Topic-Detail-Blade (topics/_blade_card) war
  # Legacy — `topic:`-Aufrufe (Dashboard, Verlauf, Dokument-Chips, alte
  # Stack-Restores) bekommen jetzt das Reiter-Blade (gleiche Card wie
  # list:topic:). Partial + Doppel-UI sind entfernt.
  def card
    @tab = "tasks"
    load_topic_show_lists
    render partial: "topics/index_list_blade", locals: { topic: @topic }, layout: false
  end

  # #435 (Hans, 2026-06-01): Listen-Blade ueber ALLE Topics. Eigener
  # Nav-Eintrag in der Sidebar (analog Tags/Aufgaben/Wissen); Klick auf ein
  # Topic haengt dessen Listen-Blade an den Stack. Collection-Action (kein
  # @topic, set_topic laeuft hier nicht).
  def topics_list_card
    @topics = Topic.visible_to(current_actor).non_templates.active.top_level.order(:name).to_a
    render partial: "topics/topics_list_blade", locals: { topics: @topics }, layout: false
  end

  # #472 (Hans, 2026-06-02): create_synthesis entfernt. Synthese-Notizen
  # entstehen jetzt ueber die Synthese-KI-Vorlagen (KiTemplate, item_type
  # synthesis) im KI-Vorlagen-Picker — kein research_kind-Mechanismus mehr.

  # #247: Listen-Blade fuer ein Topic — Sidebar-Plus appended dieselbe
  # Multi-Tab-Variante, die auch /topics/:slug initial rendert
  # (Aufgaben/Wartepunkte/Kommunikation/Wissen/Personen/Quellen-Tabs).
  # Stable-ID ist `list:topic:<slug>`, damit mehrere Topics parallel
  # im Stack stehen koennen.
  # #325 Phase 3a (Hans, 2026-05-24): Work-Tree-Render-Vorschau.
  # Eigene Stand-alone-Seite, die das Topic-Werk wie publiziert
  # darstellt (Tree-Walk via WorkTreeRender). Aufgerufen aus dem
  # Work-Tree-Tab via Vorschau-Button.
  def render_preview
    @rendered = WorkTreeRender.call(@topic, root_level: 1, number_headings: true)
    render layout: "minimal"
  end

  def list_card
    @tab = (params[:tab].presence || "tasks").to_s
    load_topic_show_lists if @tab == "tasks"
    load_topic_waiting_list if @tab == "waiting"
    load_topic_communications_list if @tab == "communications"
    load_topic_knowledge_list if @tab == "knowledge"
    load_topic_persons_list if @tab == "persons"
    load_topic_sources_list if @tab == "sources"
    render partial: "topics/index_list_blade", locals: { topic: @topic }, layout: false
  end

  # #352 (Hans, 2026-05-25): Rendering-Blade-Fragment fuer den Stack.
  # Liefert den Topic-Work-Tree als Stack-Card mit chevron-toggle-baren
  # KIs (Pendant zur statischen Render-Vorschau in `render_preview`).
  def render_card
    render partial: "topics/render_blade", locals: { topic: @topic }, layout: false
  end

  # #352-follow (Hans, 2026-05-25): Topic-Reference-Blade. Aggregiert
  # alle Wikilink-Ziele aus allen KIs im Work-Tree.
  def refs_card
    render partial: "topics/refs_blade", locals: { topic: @topic }, layout: false
  end

  def show
    @tab = (params[:tab].presence || "tasks").to_s
    @show_done = ActiveModel::Type::Boolean.new.cast(params[:show_done])
    @mine_only = ActiveModel::Type::Boolean.new.cast(params[:mine])

    # #148: Pro Tab eigene sort/dir/filter-Logik — Werte fließen in
    # URL-Query (gleiche Konvention wie die Index-Pages).
    @sort = params[:sort].to_s.presence
    @dir  = params[:dir].to_s.presence
    @q    = params[:q].to_s.strip.presence

    load_topic_show_lists                  if @tab == "tasks"
    load_topic_waiting_list                if @tab == "waiting"
    load_topic_communications_list         if @tab == "communications"
    load_topic_knowledge_list              if @tab == "knowledge"
    load_topic_persons_list                if @tab == "persons"
    load_topic_sources_list                if @tab == "sources"

    # #163 Phase 6d: /topics/:slug ist eine Blade-Stack-Seite mit
    # `list:topic` als initialer Card. URL-`?stack=`-Param erlaubt es,
    # zusaetzlich Detail-Cards (Tasks/Awaitings/KIs etc.) gleich
    # mitzu-renden.
    if params[:stack].blank?
      # #247 follow-up: slug-spezifischer Default-Stack, damit der Reload
      # einer /topics/:slug-Seite mit dem gleichen stable-id matcht, den
      # auch das Sidebar-Plus erzeugt — sonst koennten zwei Topic-Listen-
      # Cards mit verschiedenen IDs koexistieren.
      params[:stack] = "list:topic:#{@topic.slug}"
    end
    @initial_stack_items  = build_initial_stack
    @initial_stack_bodies = bodies_for_initial_stack(@initial_stack_items)
  end

  def new
    @topic = Topic.new
  end

  def create
    @topic = Topic.new(topic_params.merge(creator: current_actor))
    if @topic.save
      redirect_to topic_path(@topic), notice: "Thema angelegt"
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @topic.update(topic_params)
      record_edit_view(@topic)
      respond_to do |format|
        format.turbo_stream do
          # #567: auch die Stack-Karten (Topic-Blade + Eigenschaften-Blade)
          # live ersetzen — Targets über den ALTEN Slug (kann sich im Form
          # geändert haben), Inhalt mit dem neuen Stand. Fehlende Targets
          # sind No-Ops.
          old_slug = @topic.slug_before_last_save || @topic.slug
          render turbo_stream: [
            turbo_stream.replace("topic_detail",
              partial: "topics/detail", locals: { topic: @topic }),
            turbo_stream.replace("topic_row_#{@topic.id}",
              partial: "topics/row", locals: { topic: @topic }),
            turbo_stream.replace("stack_card_topicprops:#{old_slug}",
              partial: "topics/properties_blade_card", locals: { topic: @topic })
          ]
        end
        format.html { redirect_to topic_path(@topic), notice: "Thema gespeichert" }
      end
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @topic.destroy!
    redirect_to topics_path, notice: "Thema gelöscht"
  end

  def instantiate
    new_topic = TopicTemplateService.instantiate(
      @topic,
      new_name: params.require(:new_name),
      creator:  current_actor,
      team_id:  params[:team_id].presence
    )
    redirect_to topic_path(new_topic), notice: "Vorlage instanziiert"
  rescue TopicTemplateService::NotATemplateError => e
    redirect_to topic_path(@topic), alert: e.message
  end

  # Batch-Reorder nach Drag-and-Drop. Erwartet `ordered_task_ids=1,3,2,...`
  # und schreibt alle Positionen in einer Transaktion neu. Räumt nebenbei
  # next_step-Flags, die in der Liste landen, automatisch auf.
  #
  # Antwort: turbo_stream, das Slot + Listen frisch rendert — so fliegen
  # Tasks, die aus dem Slot in die Liste gezogen wurden, an die richtige
  # Stelle. Auf /tasks/index existieren die Target-IDs nicht und Turbo
  # ignoriert die Replace-Anweisungen still.
  def reorder_tasks
    ids = params[:ordered_task_ids].to_s.split(",").map(&:to_i).reject(&:zero?)
    TaskTopic.transaction do
      TaskTopic.where(task_id: ids, topic_id: @topic.id, next_step: true)
               .update_all(next_step: false)
      ids.each_with_index do |task_id, i|
        TaskTopic.where(task_id: task_id, topic_id: @topic.id)
                 .update_all(position: i + 1)
      end
    end
    @show_done = ActiveModel::Type::Boolean.new.cast(params[:show_done])
    @mine_only = ActiveModel::Type::Boolean.new.cast(params[:mine])
    load_topic_show_lists
    render_topic_tasks_stream
  end

  # Setzt den Next-Step für dieses Topic. Altes Next-Step-Flag wird
  # zurückgesetzt, neue Task wird gesetzt. Antwort: turbo_stream, der
  # Slot + Liste frisch rendert.
  # #494 (Hans, 2026-06-03): „Quelle aufnehmen" mit Neu-Anlegen — erstellt
  # eine minimale Quelle (nur Titel, csl_type-Default) und ordnet sie diesem
  # Thema als Recherche-Quelle (relevance: relevant) zu. Antwort: turbo_stream,
  # das die Recherche-Quellen-Sektion neu rendert.
  def create_source
    title = params[:title].to_s.strip
    if title.blank?
      head :unprocessable_content and return
    end
    source = Source.create!(title: title, csl_type: "webpage", creator: current_actor)
    SourceTopic.find_or_create_by!(source: source, topic: @topic) do |st|
      st.relevance = "relevant"
    end
    respond_to do |format|
      format.turbo_stream do
        # #494 (Hans, 2026-06-03): den Slug der frischen Quelle mitgeben, damit
        # der Picker sie gleich als Blade zur Bearbeitung im Stack oeffnet.
        response.set_header("X-Source-Slug", source.slug)
        render turbo_stream: turbo_stream.replace(
          "topic_research_sources_#{@topic.id}",
          partial: "topics/research_sources", locals: { topic: @topic })
      end
      format.html { redirect_to source_path(source.slug) }
    end
  end

  def set_next_step
    task_id = params.require(:task_id).to_i
    link = @topic.task_topics.find_by!(task_id: task_id)

    TaskTopic.transaction do
      @topic.task_topics.where(next_step: true).where.not(id: link.id)
            .update_all(next_step: false)
      link.update!(next_step: true)
    end

    @show_done = ActiveModel::Type::Boolean.new.cast(params[:show_done])
    load_topic_show_lists
    render_topic_tasks_stream
  rescue ActiveRecord::RecordInvalid => e
    render turbo_stream: turbo_stream.append("flash", html: "<div class=\"text-rose-700\">#{e.message}</div>".html_safe),
           status: :unprocessable_entity
  end

  # Entfernt den Next-Step. Task rückt an den Listenanfang (position = 1,
  # andere werden nach hinten geschoben).
  def clear_next_step
    link = @topic.task_topics.find_by(next_step: true)
    if link
      TaskTopic.transaction do
        # Alle anderen Positionen um +1 schieben, damit die ehemalige
        # Next-Step-Task vorne einsortiert werden kann.
        TaskTopic.where(topic_id: @topic.id).where.not(id: link.id)
                 .update_all("position = position + 1")
        link.update!(next_step: false, position: 1)
      end
    end
    @show_done = ActiveModel::Type::Boolean.new.cast(params[:show_done])
    @mine_only = ActiveModel::Type::Boolean.new.cast(params[:mine])
    load_topic_show_lists
    render_topic_tasks_stream
  end

  # #571: Direktsprung ins Kundenportal des Projekts — eingeloggt aus
  # Kundensicht (frischer Magic-Token des ersten aktiven Zugangs). So sieht
  # Hans mit einem Klick exakt, was der Kunde sieht.
  def portal_preview
    access = PortalAccess.active.where(topic: @topic).order(:id).first
    if access.nil?
      redirect_back fallback_location: topic_path(@topic),
        alert: "Kein aktiver Portal-Zugang — zuerst im Eigenschaften-/Portal-Bereich einen Zugang anlegen."
      return
    end
    redirect_to "https://#{PortalMailer.portal_host}/portal/session/#{access.magic_token}",
                allow_other_host: true
  end

  # #573 v2: Kalender-Reiter-Frame — nur der Zeitraum-Block (in-place-Nav).
  def calendar_tab
    render partial: "topics/index_blade_calendar_tab", layout: false, locals: { topic: @topic }
  end

  # #567: Topic-Eigenschaften als Blade-Card (statt Vollnavigation zu /edit).
  def properties_card
    render partial: "topics/properties_blade_card", layout: false, locals: { topic: @topic }
  end

  # #566: Kunde (Person/Org-KI) zuordnen — leerer value löst die Zuordnung.
  # Antwort ersetzt Chip + Topic-Blade (Portal-Sektion erscheint/verschwindet).
  def set_customer
    @topic.update!(customer_uuid: params[:value].presence)
    # #571: das Eigenschaften-Blade komplett neu rendern — Chip UND
    # Kundenportal-Sektion (erscheint/verschwindet mit der Zuordnung) leben
    # beide dort.
    render turbo_stream: turbo_stream.replace("stack_card_topicprops:#{@topic.slug}",
      partial: "topics/properties_blade_card", locals: { topic: @topic })
  end

  private

  def render_topic_tasks_stream
    streams = [
      turbo_stream.replace("next_step_slot",
        partial: "topics/next_step_slot",
        locals:  { topic: @topic, task: @next_step_task }),
      turbo_stream.replace("open_tasks_list",
        partial: "topics/open_tasks_list",
        locals:  { topic: @topic, tasks: @open_tasks }),
      turbo_stream.replace("done_tasks_list",
        partial: "topics/done_tasks_list",
        locals:  { topic: @topic, tasks: @done_tasks, show_done: @show_done })
    ]
    # Wenn der Aufrufer (z.B. Toggle aus Task-Detail-Pane) eine task_id
    # mitgegeben hat, aktualisieren wir auch deren Topics-Chips, damit
    # das Dreieck-Toggle live umspringt. Falls die Chips nicht im DOM
    # sind (z.B. echte Topic-Show), ignoriert Turbo den Stream still.
    if (toggled_task_id = params[:task_id].presence)
      task = Task.find_by(id: toggled_task_id)
      if task
        streams << turbo_stream.replace("task_topics_chips_#{task.id}",
          partial: "tasks/topics_chips", locals: { task: task })
      end
    end
    render turbo_stream: streams
  end

  def controller_action_to_capability
    return "create" if action_name == "instantiate"
    return "update" if %w[reorder_tasks set_next_step clear_next_step create_source].include?(action_name)
    super
  end

  def set_topic
    # #602 S1: unsichtbare Topics verhalten sich wie nicht existent (404).
    @topic = Topic.visible_to(current_actor).find_by!(slug: params[:slug])
  end

  def topic_params
    params.require(:topic).permit(:name, :slug, :description, :status, :color, :template,
                                  :team_id, :parent_topic_id,
                                  :work_tree_title, :work_tree_subtitle)
  end
end
