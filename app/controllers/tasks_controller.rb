class TasksController < ApplicationController
  include SlugListParams
  include TaskMemberActions
  include KnowledgeStackHelpers

  before_action :set_task,    only: [:show, :edit, :update, :destroy, :toggle_done, :create_awaiting, :set_commitment, :promote_to_topic, :publish, :unpublish, :card, :wrap_highlight, :ensure_anchor, :comment_at, :task_at, :ref_label]
  before_action :set_any_task, only: [:restore]

  def index
    load_index_state!
    # #163 Phase 6c: /tasks ist jetzt eine Blade-Stack-Seite. Default-
    # Stack = `list:tasks`. Wenn `?stack=` mitgegeben wird (z.B.
    # /tasks?stack=list:tasks,task:42), parsen wir das via BladeStackLoader.
    if params[:stack].blank?
      params[:stack] = "list:tasks"
    end
    @initial_stack_items  = build_initial_stack
    @initial_stack_bodies = bodies_for_initial_stack(@initial_stack_items)
  end

  def show
    # #211: kein Auto-Mark-as-read mehr beim Task-Visit.
    # #163 Phase 6c / #756 (Hans, 2026-06-23): /tasks/:id leitet IMMER zur
    # Stack-Variante um. Die frühere Frame-Detailansicht (show.html.erb →
    # tasks/_detail im `task_detail`-Frame) ist aus dem Interface nicht mehr
    # erreichbar und wurde entfernt — ein Direktaufruf/Bookmark landet im Stack.
    redirect_to tasks_path(stack: "list:tasks,task:#{@task.id}")
  end

  # #163 Phase 2: Card-Fragment fuer den Blade-Stack. Liefert ein Task-
  # Blade (Spine + Detail), das der blade-stack-Controller appended.
  # Analog zu KnowledgeStackController#card und SourcesController#card.
  def card
    render partial: "tasks/blade_card", locals: { task: @task }, layout: false
  end

  # #534 (Hans, 2026-06-06): leichter JSON-Resolver für den CM6-Editor, damit
  # Aufgaben-Wikilinks `[[#id]]` schon im Bearbeitungsmodus als „#id Titel"-
  # Pille gerendert werden können (analog zum Read-Mode). Nicht gefundene IDs
  # liefern 404 (set_task) → der Editor stylt sie als „missing".
  def ref_label
    render json: { found: true, id: @task.id, title: @task.title.to_s }
  end

  # #163 Phase 5a-2: Listen-Blade fuer den Cross-Entity-Stack. Wird vom
  # Sidebar-Plus-Icon „Aufgaben" gefetcht und von BladeStackLoader bei
  # `list:tasks` im ?stack=-Param serverseitig gerendert. Die Daten-
  # Befuellung steckt im Partial — beide Render-Pfade brauchen dieselbe
  # Liste, ohne dass jeder Caller sie wiederholt aufbauen muss.
  # #275: dieselbe Rich-Blade rendern, die /tasks initial zeigt — der
  # ueber das Sidebar-Plus angehaengte Tasks-Blade soll genauso aussehen
  # wie der initiale. load_index_state! befuellt die @-Vars, die das
  # index_list_blade-Partial braucht (Sektionen/Toolbar/Sort/Filter).
  def list_card
    load_index_state!
    render partial: "tasks/index_list_blade", layout: false
  end

  # JSON-Endpoint für den Task-Picker (Dependency-Autocomplete).
  # Liefert bis zu 10 offene Tasks nach Titel-Substring;
  # exclude_ids filtert Tasks raus (Self + bestehende Preds/Succs).
  def suggest
    q       = params[:q].to_s.strip
    exclude = params[:exclude_ids].to_s.split(",").map(&:to_i).reject(&:zero?)

    scope = Task.visible_to(current_actor).open
    scope = scope.where("LOWER(title) LIKE ?", "%#{q.downcase}%") if q.present?
    scope = scope.where.not(id: exclude) if exclude.any?
    results = scope.order(:title).limit(10).pluck(:id, :title)
    render json: { items: results.map { |id, title| { id: id, label: title } } }
  end

  # #162: JSON-Endpoint für den Tag-Picker (Autocomplete + hybrider
  # Quick-Create). Liefert distinct Tags aus Task.tags, gefiltert auf
  # den Query-String. Limit ist großzügig — Tag-Vokabular bleibt klein.
  def suggest_tags
    # #428 (Hans, 2026-05-31): aus der zentralen Tag-Registry — gemeinsames
    # Vokabular ueber Tasks UND KnowledgeItems hinweg, damit z.B. "idee" auch
    # hier vorgeschlagen wird, wenn es bisher nur an KIs benutzt wurde.
    tags = Tag.vocabulary(params[:q])
    render json: { items: tags.first(20).map { |t| { slug: t, label: t } } }
  end

  def new
    @task = Task.new
  end

  def create
    # Default-Zuweisung an Current.actor passiert im Task-Model
    # (before_validation). Explizite assignee_id im Formular hat Vorrang.
    # #167: published_at-Default kommt ebenfalls aus dem Model
    # (Agent-Assignee → Draft, sonst sofort live).
    @task = Task.new(task_params.merge(creator: current_actor))
    # #739 (Hans): Quick-Anlage ohne Titel soll NICHT an der Titel-
    # Validierung scheitern (vorher: rescue → render :new = Sprung aus dem
    # Stack, nichts angelegt). Stattdessen mit Platzhalter anlegen und den
    # Cursor ins (selektierte) Titelfeld der frisch angehängten Card setzen.
    @blank_title = @task.title.blank?
    @task.title = "Neue Aufgabe" if @blank_title
    topic_id = params[:topic_id].presence || @task.topics.first&.id
    topic = nil

    Task.transaction do
      @task.save!
      if topic_id
        topic = Topic.find(topic_id)
        position = (topic.task_topics.maximum(:position) || 0) + 1
        TaskTopic.create!(task: @task, topic: topic, position: position)
      end
    end

    # Subtask-Erstellung aus dem Detail-Panel: frisches Detail der Eltern-
    # Aufgabe. #163: Refresh ueber inneren `task_<id>`-Div statt
    # `task_detail`-Frame — wirkt sowohl in der Legacy-Frame-Page als
    # auch in der Blade-Card.
    if @task.parent_id
      parent = @task.parent
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.replace_all("#task_#{parent.id}",
            partial: "tasks/detail_body", locals: { task: parent })
        end
        format.html { redirect_to task_path(parent), notice: "Unteraufgabe angelegt" }
      end
      return
    end

    # #153 Follow-up: Quick-Add aus dem Per-Agent-Dashboard (#564: Streams
    # in create_streams_for_agent gebündelt).
    if (agent_target = params[:agent_target].presence)
      respond_to do |format|
        format.turbo_stream { render turbo_stream: create_streams_for_agent(agent_target.to_i) }
        format.html { redirect_to dashboard_path }
      end
      return
    end

    # Quick-Add aus einer Sektion auf /tasks (Eingang/Heute/Demnächst/Später,
    # Wann- oder Topic-View). Row in die passende Liste anhängen und Form
    # mit autofokus neu rendern, damit man Aufgaben in Reihe eintippen kann.
    if (section_key = params[:section_target].presence)
      quickadd_topic_id = params[:quickadd_topic_id].presence
      target_list_id = if quickadd_topic_id
                         topic = Topic.find_by(id: quickadd_topic_id)
                         topic ? "tasks_topic_#{topic.slug}" : "tasks_topic_none"
                       elsif params[:topic_target].present?
                         "tasks_topic_none"
                       else
                         "tasks_section_#{section_key}"
                       end
      form_id = "section_quickadd_#{section_key}_#{quickadd_topic_id || 'none'}"

      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: create_streams_for_section(target_list_id, form_id,
                                                          section_key, quickadd_topic_id)
        end
        format.html { redirect_to tasks_path }
      end
      return
    end

    respond_to do |format|
      format.turbo_stream { render turbo_stream: create_streams_default(topic) }
      format.html do
        if topic
          redirect_to topic_path(topic)
        else
          redirect_to tasks_path
        end
      end
    end
  rescue ActiveRecord::RecordInvalid
    render :new, status: :unprocessable_entity
  end

  def edit
  end

  def update
    contacts_param = params.dig(:task, :contacts)

    if @task.update(task_params)
      sync_contacts_by_slugs(@task, contacts_param) unless contacts_param.nil?
      record_edit_view(@task)
      topic = topic_context || @task.topics.first
      desc_changed = @task.saved_change_to_description?
      respond_to do |format|
        format.turbo_stream do
          # Bewusst KEIN Replace von #task_detail: das stompt Felder,
          # in denen der User gerade tippt (Wechsel aus Priority/Tags
          # direkt in die Beschreibung führte sonst zu zwei flackernden
          # DOM-Ständen, weil der Stream die Form ersetzt während der
          # Cursor schon im neuen Feld ist). Einzelfelder sind lokal
          # bereits korrekt; nur die Row in der Liste muss synchron.
          # #286: blade_kind/blade_id mitgeben — sonst rendert das Row-
          # Partial das Plus-Icon nicht mehr, und nach Update einer im
          # Dashboard-Agent-Slot prepended Task verschwindet das Plus.
          # Auf Seiten ohne blade-stack ist der Plus-Button ein No-Op
          # (blade-link-Controller prueft document.body has-blade-stack).
          streams = [
            turbo_stream.replace_all("#task_row_#{@task.id}",
              partial: "tasks/row",
              locals: { task: @task, topic: topic,
                        blade_kind: "task", blade_id: @task.id })
          ]
          # #132 Phase 2: Beschreibungs-Preview live aktualisieren, wenn
          # sich die description geändert hat. Andere Felder lassen das
          # Description-Partial unangetastet, damit der Cursor nicht
          # springt, falls der User schon dort tippt.
          if desc_changed
            streams << turbo_stream.replace_all("#task_description_#{@task.id}",
              partial: "tasks/description", locals: { task: @task })
          end
          # #603 R6 (Hans): nach Änderung der vier Kopf-Felder den
          # Felder-Block neu rendern — Icons (Wann/Priorität) springen
          # automatisch um, offene Eingabefelder (Zuständig/Datum)
          # schließen und zeigen den neuen Wert. Stompt nichts, weil
          # der Block keine Freitext-Eingaben enthält.
          if (@task.saved_changes.keys & %w[assignee_id due_date commitment priority]).any?
            streams << turbo_stream.replace_all("#task_fields_#{@task.id}",
              partial: "tasks/detail_field_rows", locals: { task: @task })
            # #603 R8: Header-Summary (Icons) ebenfalls aktualisieren.
            streams << turbo_stream.replace_all("#task_fields_summary_#{@task.id}",
              partial: "tasks/fields_summary", locals: { task: @task })
          end
          render turbo_stream: streams
        end
        format.html { redirect_to task_path(@task), notice: "Aufgabe gespeichert" }
      end
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # Soft-Delete: deleted_at wird gesetzt, default_scope blendet die Task aus.
  # Toast mit Undo-Link auf POST /tasks/:id/restore. Cron räumt nach
  # 30 Tagen hart auf.
  def destroy
    topic = @task.topics.first
    @task.discard!
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: [
          turbo_stream.remove("task_row_#{@task.id}"),
          # #756 (Hans, 2026-06-23): Legacy `task_detail`-Frame-Replace
          # entfernt (Frame-Detailansicht nicht mehr erreichbar).
          # #163: Blade-Pages: die Card aus dem Stack ziehen.
          turbo_stream.remove("stack_card_task:#{@task.id}"),
          helpers.toast_stream(
            message:  "Aufgabe '#{@task.title.truncate(40)}' gelöscht",
            undo_url: restore_task_path(@task),
            undo_payload: {}
          )
        ]
      end
      format.html do
        flash[:notice] = "'#{@task.title.truncate(40)}' in den Papierkorb gelegt."
        if topic
          redirect_to topic_path(topic)
        else
          redirect_to tasks_path
        end
      end
    end
  end

  def restore
    @task.undiscard!
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: helpers.toast_stream(
          message: "'#{@task.title.truncate(40)}' wiederhergestellt"
        )
      end
      format.html { redirect_to tasks_path, notice: "Wiederhergestellt." }
    end
  end

  def trash
    @discarded = Task.discarded.order(deleted_at: :desc).limit(100)
  end

  # POST /tasks/bulk_update
  # #388 (Hans, 2026-05-28): Batch-Edit fuer Aufgabenlisten. Erwartet
  # ids[] (Pflicht) und optional: assignee_id, status, priority,
  # add_topic_id, remove_topic_id. Nur uebergebene Felder werden
  # gesetzt; Topic-Aenderungen sind additiv (kein Replace), so dass die
  # bestehende Topic-Mitgliedschaft erhalten bleibt.
  def bulk_update
    ids = Array(params[:ids]).map(&:to_i).uniq.reject(&:zero?)
    if ids.empty?
      respond_to do |format|
        format.turbo_stream { render turbo_stream: helpers.toast_stream(message: "Nichts ausgewaehlt.") }
        format.json        { render json: { error: "no ids" }, status: :unprocessable_entity }
      end
      return
    end

    tasks = Task.where(id: ids)
    updates = {}
    updates[:assignee_id] = params[:assignee_id].to_i if params[:assignee_id].present?
    updates[:assignee_id] = nil                       if params[:assignee_id] == "none"
    updates[:status]      = params[:status]           if params[:status].present?
    updates[:priority]    = params[:priority]         if params[:priority].present?
    add_topic_id = params[:add_topic_id].presence&.to_i

    changed = 0
    Task.transaction do
      tasks.find_each do |t|
        t.assign_attributes(updates) if updates.any?
        t.save!
        if add_topic_id && Topic.exists?(id: add_topic_id)
          t.task_topics.find_or_create_by!(topic_id: add_topic_id)
        end
        changed += 1
      end
    end

    summary = "#{changed} Aufgaben aktualisiert."
    respond_to do |format|
      format.turbo_stream { render turbo_stream: helpers.toast_stream(message: summary) }
      format.json        { render json: { changed: changed } }
      format.html         { redirect_back fallback_location: tasks_path, notice: summary }
    end
  end

  # #203 Phase E.2: create_awaiting, set_commitment, publish,
  # toggle_done, promote_to_topic leben jetzt im TaskMemberActions-Concern.

  # #572: Meilenstein-Flag togglen — Antwort ersetzt NUR das Icon in der
  # Blade-Leiste (sofort sichtbares Rot/Grau) + die Listen-Row (Rauten-Marker).
  def toggle_milestone
    @task = Task.visible_to(current_actor).find(params[:id])
    @task.update!(client_milestone: !@task.client_milestone)
    render turbo_stream: [
      turbo_stream.replace("task_milestone_btn_#{@task.id}",
        partial: "tasks/milestone_button", locals: { task: @task }),
      turbo_stream.replace("task_row_#{@task.id}",
        partial: "tasks/row", locals: { task: @task, topic: @task.topics.first,
                                        blade_kind: "task", blade_id: @task.id })
    ]
  end

  private

  # Lädt alles, was die Index-Liste braucht. Wird sowohl von index als
  # auch von show (bei Vollbild-Render) aufgerufen. Die Filter-/Sortier-
  # Logik selbst lebt in TaskQuery (#127).
  # #203 Phase E.7: gesamten Index-State in TaskIndexState ausgelagert.
  # Hier nur noch das Mapping ins Instanz-Var-Namespace, das die Views
  # erwarten — die echte Logik (Group-Mode, Filter, Sections) liegt im
  # Form-Object und ist isoliert testbar.
  def load_index_state!
    TaskAutoPromote.run!(current_actor)
    state = TaskIndexState.new(params: params, actor: current_actor)
    @group_by           = state.group_by
    @show_done          = state.show_done
    @task_status        = state.task_status
    @filter_q           = state.q
    @filter_tag         = state.tag
    @filter_priority    = state.priority
    @filter_assignee_id = state.assignee_id
    @filter_kind        = state.kind
    @sort               = state.sort
    @dir                = state.dir
    @tasks              = state.tasks
    @sections           = state.sections
    @topic_sections     = state.topic_sections
    @trash_count        = state.trash_count
  end

  def controller_action_to_capability
    return "update" if action_name == "toggle_done"
    return "update" if action_name == "set_commitment"
    return "update" if action_name == "restore"
    return "read"   if action_name == "trash"
    return "create" if action_name == "create_awaiting"
    return "update" if action_name == "promote_to_topic"
    return "read"   if action_name == "suggest_tags"
    return "update" if action_name == "bulk_update"
    return "update" if action_name == "wrap_highlight"
    # #480 Inc.3: ensure_anchor mutiert die Description (update); comment_at/
    # task_at legen ein neues KI bzw. eine neue Aufgabe an (create).
    return "update" if action_name == "ensure_anchor"
    return "create" if %w[comment_at task_at].include?(action_name)
    super
  end

  # create_awaiting legt ein Awaiting an, nicht einen Task.
  def controller_resource_type
    return "Awaiting" if action_name == "create_awaiting"
    super
  end

  def parse_date(raw)
    raw.present? ? Date.parse(raw) : nil
  rescue ArgumentError
    nil
  end

  def set_task
    # #221: die card-Action rendert _detail_body mit pickers/_summary, das
    # liest topics/attachments/predecessors/successors/subtasks/mentioned_kis/
    # sources — preloaden statt 8 einzelner COUNT-Queries.
    # #602 S1: Lese-Pfad immer durch den Sichtbarkeits-Scope.
    scope = action_name == "card" ?
              Task.visible_to(current_actor).includes(:topics, :attachments,
                            :predecessors, :successors,
                            :subtasks, :mentioned_kis,
                            :sources) :
              Task.visible_to(current_actor)
    @task = scope.find(params[:id])
  end

  # Findet Tasks unabhängig vom soft-delete-Status — für Restore-Action.
  def set_any_task
    @task = Task.with_discarded.visible_to(current_actor).find(params[:id])
  end

  def topic_context
    slug = params[:topic_slug].presence
    return nil unless slug
    Topic.visible_to(current_actor).find_by(slug: slug)
  end


  # ── #564: Turbo-Stream-Bündel der drei create-Pfade ────────────────────────
  # Die Targets sind der Vertrag zum DOM (Tests: tasks_controller_test) —
  # hier gebündelt statt inline in create, damit der Action-Fluss lesbar bleibt.

  # Gemeinsamer Schwanz aller create-Antworten: frische Task als Blade-Card
  # rechts in den Stack appenden (#218/#382; blade_stack_container existiert
  # nur auf Stack-Pages, sonst No-Op; #270/#281: Cursor ins Beschreibungs-Feld).
  # #756 (Hans, 2026-06-23): der frühere Legacy-Replace des `task_detail`-Frames
  # ist entfernt — diese Frame-Detailansicht ist aus dem Interface nicht mehr
  # erreichbar (alle Listen öffnen Aufgaben als Blade-Card im Stack).
  def create_streams_tail
    [
      turbo_stream.append("blade_stack_container",
        # #739 (Hans): bei leerem Titel Cursor ins Titelfeld (Platzhalter
        # selektiert) statt ins Beschreibungsfeld.
        partial: "tasks/blade_card", locals: { task: @task, focus: @blank_title ? :title : :description })
    ]
  end

  # Quick-Add aus dem Per-Agent-Dashboard: Row in die agent-spezifische Liste
  # prependen, Empty-State entfernen, Form mit Autofokus neu rendern.
  # #235: blade_kind/blade_id mitgeben, sonst rendert das row-Partial mit dem
  # viewport-frame-Default.
  def create_streams_for_agent(agent_id)
    [
      turbo_stream.remove("agent_tasks_empty_#{agent_id}"),
      turbo_stream.prepend("agent_tasks_#{agent_id}",
        partial: "tasks/row",
        locals: { task: @task, topic: @task.topics.first, show_topic: true,
                  blade_kind: "task", blade_id: @task.id, link_path: task_path(@task) }),
      turbo_stream.replace("agent_quickadd_#{agent_id}",
        partial: "dashboard/agent_quickadd",
        locals: { agent_id: agent_id, autofocus: true })
    ] + create_streams_tail
  end

  # Quick-Add aus einer Sektion auf /tasks. #135: prepend statt append —
  # neue Tasks tauchen oben in der Sektion auf.
  def create_streams_for_section(target_list_id, form_id, section_key, quickadd_topic_id)
    [
      turbo_stream.prepend(target_list_id,
        partial: "tasks/row",
        locals: { task: @task, topic: @task.topics.first, show_topic: quickadd_topic_id.blank?,
                  blade_kind: "task", blade_id: @task.id, link_path: task_path(@task) }),
      turbo_stream.replace(form_id,
        partial: "tasks/section_quickadd",
        locals: { section_key: section_key,
                  topic_id: quickadd_topic_id,
                  autofocus: true })
    ] + create_streams_tail
  end

  # Standard-Pfad (Topic-Seite oder /tasks ohne Sektion).
  def create_streams_default(topic)
    streams = [
      turbo_stream.remove("tasks_empty"),
      turbo_stream.prepend("open_tasks_list",
        partial: "tasks/row",
        locals: { task: @task, topic: topic,
                  blade_kind: "task", blade_id: @task.id })
    ] + create_streams_tail
    if topic
      streams << turbo_stream.replace("task_quickadd_form",
        partial: "tasks/quickadd_form", locals: { topic: topic, autofocus: true })
    end
    streams
  end

  def task_params
    # Quick-Add-Forms (Dashboard-Agent-Slot, Sektion-Header, Topic-Tab)
    # posten `title`/`description`/`commitment`/`assignee_id` UN-genested
    # — direkt als Top-Level-Params. Das volle New-/Edit-Formular nestet
    # alles unter `task[...]`. Erkennung: Top-Level-`title` vorhanden UND
    # kein `task[title]`. (#299: description kommt vom TaskTemplate-
    # Picker; #153: assignee_id aus dem Per-Agent-Quickadd.)
    #
    # Wichtig: der Sektion-Quickadd postet zusaetzlich `task[topic_ids][]`
    # — d.h. ein :task-Key EXISTIERT, traegt aber keinen title. Die
    # `dig(:task, :title)`-Pruefung faengt genau diesen Fall mit ab,
    # waehrend das alte rescue-ParameterMissing-Konstrukt hier nicht
    # gegriffen haette (require(:task) wirft nicht, wenn :task da ist).
    # #739 (Hans): `key?` statt `present?` — ein LEERES Top-Level-`title`
    # (Quick-Add ohne Titelangabe) muss diesen Zweig auch nehmen, sonst
    # landet es bei require(:task) → ParameterMissing → keine Anlage.
    if params.key?(:title) && params.dig(:task, :title).blank?
      h = params.permit(:title, :description, :commitment, :assignee_id).to_h
      h[:status] ||= "open"
      h.delete(:commitment)  if h[:commitment].blank?
      h.delete(:description) if h[:description].blank?
      return h
    end

    permitted = params.require(:task).permit(:title, :description, :status, :priority,
                                             :due_date, :completed_at, :commitment,
                                             :client_milestone,
                                             :assignee_id, :parent_id, :communication_id,
                                             :tag_list)
    # "Eingang" ist im Select ein leerer String — DB-Wert ist NULL.
    permitted[:commitment] = nil if permitted[:commitment] == ""
    # tag_list ist ein virtuelles Komma-getrenntes String-Field im
    # Edit-Form; vom FormBuilder als task[tag_list] gepostet. In das
    # tatsächliche tags-Array konvertieren und das virtuelle Feld weg.
    if permitted.key?(:tag_list)
      raw = permitted.delete(:tag_list)
      permitted[:tags] = raw.to_s.split(",").map(&:strip).reject(&:blank?)
    end
    permitted
  end

  # Analog zu KnowledgeItems: ein komma-getrenntes Slug-Feld synct
  # task.mentioned_kis atomar auf den neuen Stand. Slugs werden auf
  # Person/Org-KIs gemappt; fehlende werden angelegt.
  def sync_contacts_by_slugs(task, value)
    slugs = split_slugs(value)
    return if slugs.nil?
    target_uuids = slugs.filter_map { |s| PersonKiResolver.find_or_create!(s, actor: current_actor)&.uuid }
    MentionReconciler.reconcile!(task.task_mentions, target_uuids)
  end
end
