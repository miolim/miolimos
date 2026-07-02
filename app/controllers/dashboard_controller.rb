class DashboardController < ApplicationController
  include KnowledgeStackHelpers

  def index
    load_dashboard_sections!

    # #214 / #163 Phase 5b-2: rechte Sektionen liegen jetzt im Blade-
    # Stack. Phase 6c: die linken Sektionen werden zur ersten Blade
    # (`list:dashboard`) — die ganze Seite ist ein durchgehender Stack.
    # Initial-State kommt aus `?stack=`-Param. Legacy-Params
    # `?task=X` / `?awaiting=Y` / `?communication=Z` werden auf das
    # Stack-Format gemappt, damit alte Dashboard-Links weiter funktionieren.
    if params[:stack].blank?
      legacy_tokens = ["list:dashboard"]
      legacy_tokens << "task:#{params[:task]}"                   if params[:task].present?
      legacy_tokens << "awaiting:#{params[:awaiting]}"           if params[:awaiting].present?
      legacy_tokens << "communication:#{params[:communication]}" if params[:communication].present?
      params[:stack] = legacy_tokens.join(",")
    end
    @initial_stack_items  = build_initial_stack
    @initial_stack_bodies = bodies_for_initial_stack(@initial_stack_items)
  end

  # #434 (Hans, 2026-06-01): Standalone-Card des list:dashboard-Blades.
  # Der Stack-Restore (Verlauf-Drawer) baut das erste Blade per
  # appendCardBare(<stack-id>) -> _urlForStackId -> /dashboard/list_card
  # wieder auf. Vorher fehlte als einzigem list:-Typ dieser Endpoint, der
  # Restore-Fetch lief in 404 und das Dashboard-Blade wurde stillschweigend
  # weggelassen. Rendert dieselben Sektionen wie #index, ohne Layout —
  # analog tasks#list_card.
  def list_card
    load_dashboard_sections!
    render partial: "dashboard/index_list_blade", layout: false
  end

  # #393 (Hans, 2026-05-28): „Alle als gelesen markieren". Erwartet
  # ids[] (Task-IDs), upsertet pro Task einen ActorView-Stempel fuer
  # den aktuellen Actor. Beim naechsten Dashboard-Load fallen die
  # zugehoerigen Replies aus der Unread-Sektion. Antwort: Turbo-Stream
  # der das ganze Listen-Blade neu rendert.
  def mark_read
    ids = Array(params[:ids]).map(&:to_i).uniq.reject(&:zero?)
    ids = Task.where(assignee_id: AgentActor.pluck(:id)).pluck(:id) if ids.empty?
    # #401 (Hans, 2026-05-28): NICHT `ActorView.upsert_for!` — das
    # mergt mit einem View aus dem dedupe-Fenster und laesst
    # `viewed_at` unveraendert. Wir wollen aber genau diesen Zeitpunkt
    # als „gelesen bis hier"-Stempel setzen. Deshalb explizit den
    # neuesten Eintrag pro Task touchen oder anlegen.
    now = Time.current
    ids.each do |tid|
      existing = ActorView.where(actor_id:      current_actor.id,
                                 viewable_type: "Task",
                                 viewable_id:   tid)
                          .order(viewed_at: :desc)
                          .first
      if existing
        existing.update!(viewed_at: now)
      else
        ActorView.create!(actor_id:      current_actor.id,
                          viewable_type: "Task",
                          viewable_id:   tid,
                          viewed_at:     now,
                          duration_ms:   0,
                          was_edited:    false)
      end
    end
    respond_to do |format|
      format.turbo_stream { redirect_to dashboard_path }
      format.html         { redirect_to dashboard_path, notice: "Als gelesen markiert: #{ids.size}" }
    end
  end

  private

  # #434 (Hans, 2026-06-01): Daten fuer die Dashboard-Sektionen (Agent-
  # Bundles, Heute, Demnaechst, Process-Edge, Recent-Communications).
  # Aus #index extrahiert, damit #list_card das list:dashboard-Blade
  # standalone (ohne Stack-Init) re-rendern kann.
  def load_dashboard_sections!
    @show_done = ActiveModel::Type::Boolean.new.cast(params[:show_done])

    # Auto-Promote läuft auch hier — sonst sähe man am Morgen mit fälligen
    # Tasks ein leeres "Heute".
    TaskAutoPromote.run!(current_actor)

    # #578: tasks/_row liest topics/assignee/subtasks/predecessors je
    # Zeile — ohne Preload sind das 4 Queries pro Task.
    scope = Task.where(assignee_id: current_actor.id)
                .without_template_tasks
                .includes(:topics, :assignee, :subtasks, :predecessors)
                .order(priority: :desc, due_date: :asc)
    scope = @show_done ? scope.where(status: [:open, :done]) : scope.open
    @today_tasks = scope.where(commitment: :today).to_a
    @soon_tasks  = scope.where(commitment: :soon).to_a

    # Prozess-Edge: pro Thema der Next-Step und die offenen Awaitings.
    # Das ist der Kopf der Pipeline je Thema — "was geht als Nächstes
    # voran, und worauf warte ich dort?"
    @process_edge_by_topic = build_process_edge
    @orphan_awaitings      = Awaiting.visible_to(current_actor).open.where(
      id: Awaiting.open.left_joins(:awaiting_topics).where(awaiting_topics: { id: nil }).select(:id)
    ).by_urgency

    # #221: Topics-Preload — die _index_list_blade-View iteriert
    # `comm.topics.each` pro Eintrag, sonst N+1.
    @recent_communications = Communication.visible_to(current_actor).includes(:topics).order(sent_at: :desc).limit(20)

    # #153: Pro AgentActor ein Daten-Bündel für das Dashboard — die alte
    # Trio-Aufteilung (Builder-Status / globale Inbox / globale Activity)
    # ist mit zwei Agenten unübersichtlich. Jeder Agent bekommt jetzt:
    # offene Tasks (assignee), ungelesene Kommentare auf seinen Tasks,
    # Activity-Stream seiner eigenen Aktionen.
    @agent_bundles = build_agent_bundles
  end

  # #153: Pro aktiven Agent ein Daten-Bündel. Keine includes-Magie über
  # `joins` hinaus — die Listen sind kurz (max 30 Einträge), N+1 ist
  # hier kein echtes Risiko.
  #
  # #393 (Hans, 2026-05-28): Nach Cutover #384 sind Comments jetzt
  # Reply-KIs (item_type=:reply, parent_type="Task"). Tracking wechselt
  # damit auf KnowledgeItem-Querys statt TaskComment. „Ungelesen" ist
  # definiert als „Reply existiert, die nach dem letzten ActorView des
  # aktuellen Users auf der Parent-Task entstanden ist". Per-Reply-Mark-
  # as-read fliegt damit raus — Hans hat das explizit als „kann neu
  # getrackt werden, aktueller Stand braucht nicht erhalten bleiben"
  # freigegeben.
  def build_agent_bundles
    agents = AgentActor.where(active: true, show_in_dashboard: true)
                       .order(:name).to_a
    return [] if agents.empty?

    reply_enum  = KnowledgeItem.item_types[:reply]
    last_views  = ActorView.where(actor_id: current_actor.id, viewable_type: "Task")
                           .group(:viewable_id)
                           .maximum(:viewed_at)

    # #457 (Hans, 2026-06-02): Gesamtzahl ALLER (veroeffentlichten)
    # Antworten je Task — fuer das `(##)` im Aktivitaets-Eintrag. Zaehlt
    # alle Autoren (auch Hans), nicht nur den Agenten.
    total_reply_counts = KnowledgeItem
                           .where(item_type: reply_enum, parent_type: "Task")
                           .where.not(published_at: nil)
                           .group(:parent_id_int).count

    agent_replies = KnowledgeItem
                      .where(item_type: reply_enum, parent_type: "Task",
                             creator_id: agents.map(&:id))
                      .where.not(published_at: nil)
                      .includes(:creator)
                      .order(created_at: :desc)
                      .to_a

    # Tasks vor-laden, damit der View task.title / task.topics rendern
    # kann (Replies sind ueber parent_id_int verknuepft, nicht ueber
    # ActiveRecord-Assoziation).
    task_ids = agent_replies.map(&:parent_id_int).uniq
    tasks_by_id = Task.where(id: task_ids)
                      .includes(:topics, :assignee, :subtasks, :predecessors).index_by(&:id)

    agents.map do |agent|
      open_tasks = Task.open
                       .without_template_tasks
                       .where(assignee_id: agent.id)
                       .includes(:topics, :assignee, :subtasks, :predecessors)
                       .order(created_at: :desc)
                       .to_a

      mine = agent_replies.select { |r| r.creator_id == agent.id }
                          .filter_map { |r| wrap_reply_for_dashboard(r, tasks_by_id) }

      unread = mine.select do |entry|
        # #393 Iter 2 (Hans, 2026-05-30): ActorView.viewable_id ist eine
        # varchar-Spalte (polymorphisch fuer Task-IDs UND KI-UUIDs), die
        # `group(:viewable_id).maximum(...)`-Map kommt deshalb mit
        # String-Keys. Wenn wir mit dem int task.id nachschlagen, ist
        # die Antwort immer nil → ALLE Replies bleiben dauerhaft
        # „unread", der zentrale Mark-Read-Button schien wirkungslos.
        last_seen = last_views[entry[:task].id.to_s]
        last_seen.nil? || entry[:reply].created_at > last_seen
      end

      # #457 (Hans, 2026-06-02): Aktivitaet je Aufgabe zusammenfassen —
      # nur die juengste Aktivitaet pro Task, plus die Gesamtzahl der
      # Aktivitaeten dieser Task. `mine` ist bereits created_at-DESC, also
      # ist der erste Eintrag pro Gruppe der juengste. Sortierung der
      # Gruppen nach ihrer juengsten Aktivitaet (DESC).
      activity = mine.group_by { |e| e.task.id }.values.map { |entries|
        { entry: entries.first,
          count: total_reply_counts[entries.first.task.id] || entries.size }
      }.sort_by { |h| h[:entry].created_at }.reverse.first(30)

      {
        agent:    agent,
        tasks:    open_tasks,
        unread:   unread,
        activity: activity
      }
    end
  end

  # Reply-KI in eine Struct packen, die _agent_section.html.erb
  # erwartet (.task, .id, .created_at, .body). Struct (statt Hash),
  # damit `bundle[:unread].group_by(&:task)` funktioniert.
  ReplyEntry = Struct.new(:reply, :task, :id, :body, :created_at, keyword_init: true)

  def wrap_reply_for_dashboard(reply, tasks_by_id)
    task = tasks_by_id[reply.parent_id_int]
    return nil unless task
    ReplyEntry.new(
      reply:      reply,
      task:       task,
      id:         reply.uuid,
      body:       reply.body,
      created_at: reply.created_at
    )
  end

  # Liefert eine Liste von Hashes { topic:, next_step:, awaitings: } für
  # jedes non-template-Topic, das entweder einen Next-Step oder offene
  # Awaitings hat. Andere Themen werden unterschlagen, damit das
  # Dashboard nicht von leeren Karten überwuchert wird.
  #
  # #221: Bulk-Loads statt pro-Topic-Queries. Vorher zwei N+1: eine pro
  # `topic.next_step_task` (JOIN task_topics WHERE next_step=true), eine
  # pro `topic.awaitings.includes(:contact_ki).open.by_urgency`. Bei N
  # Topics waren das 2N Queries. Jetzt 4 Queries gesamt.
  def build_process_edge
    topics = Topic.visible_to(current_actor).non_templates.active.order(:name).to_a
    return [] if topics.empty?
    topic_ids = topics.map(&:id)

    # Next-Step-Task pro Topic.
    next_step_pairs = TaskTopic.where(next_step: true, topic_id: topic_ids)
                               .pluck(:topic_id, :task_id)
    next_step_task_ids = next_step_pairs.map(&:last).uniq
    next_step_tasks = Task.visible_to(current_actor).where(id: next_step_task_ids)
                          .includes(:topics, :assignee, :subtasks, :predecessors).index_by(&:id)
    next_step_by_topic_id = next_step_pairs.to_h.transform_values { |task_id| next_step_tasks[task_id] }

    # Offene Awaitings pro Topic, sortiert nach Urgency.
    awaiting_pairs = AwaitingTopic.where(topic_id: topic_ids)
                                  .joins(:awaiting).merge(Awaiting.open)
                                  .pluck(:topic_id, :awaiting_id)
    awaiting_ids = awaiting_pairs.map(&:last).uniq
    awaitings = Awaiting.visible_to(current_actor).where(id: awaiting_ids).includes(:contact_ki)
                        .by_urgency.index_by(&:id)
    awaitings_by_topic_id = Hash.new { |h, k| h[k] = [] }
    awaiting_pairs.each do |t_id, a_id|
      rec = awaitings[a_id]
      awaitings_by_topic_id[t_id] << rec if rec
    end
    # Innerhalb eines Topics noch nach Urgency sortieren (pluck-Reihenfolge ist join-bedingt).
    awaitings_by_topic_id.each_value { |arr| arr.sort_by! { |a| a.follow_up_at || Date.new(9999, 1, 1) } }

    topics.filter_map do |topic|
      next_step = next_step_by_topic_id[topic.id]
      awaitings_for_topic = awaitings_by_topic_id[topic.id]
      next if next_step.nil? && awaitings_for_topic.empty?
      { topic: topic, next_step: next_step, awaitings: awaitings_for_topic }
    end
  end

  def controller_resource_type
    "Task"
  end

  # #564: mark_read ist POST mit Lese-Semantik (markiert Kommentare nur für
  # den eigenen Actor als gelesen) — bewusste Ausnahme vom fail-closed-Default.
  def controller_action_to_capability
    action_name == "mark_read" ? "read" : super
  end
end
