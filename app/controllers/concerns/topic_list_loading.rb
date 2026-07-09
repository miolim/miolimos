# #803 (aus #801 R2): Die fünf load_topic_*-Lader + ihre Sort-/Filter-
# Helfer aus dem TopicsController extrahiert — reine Param→Ivar-Glue-Schicht
# für die Topic-Tab-Listen (Wartepunkte, Kommunikation, Wissen, Personen,
# Quellen, Aufgaben). Reines Code-Move, KEIN Verhalten geändert; die
# Ivar-Namen sind der View-Vertrag und bleiben identisch.
module TopicListLoading
  extend ActiveSupport::Concern

  private

  # #148: Wartepunkte im Topic-Tab — gleiche Filter/Sort-Konventionen
  # wie auf /awaitings, gescopt auf das Topic.
  def load_topic_waiting_list
    @awaiting_overdue_only  = ActiveModel::Type::Boolean.new.cast(params[:overdue])
    @awaiting_show_resolved = ActiveModel::Type::Boolean.new.cast(params[:show_resolved])
    scope = @topic.awaitings.includes(:contact_ki)
    scope = @awaiting_show_resolved ? scope.where(status: [:open, :resolved]) : scope.open
    scope = scope.where("follow_up_at < ?", Date.today) if @awaiting_overdue_only
    if @q
      like = "%#{@q.downcase}%"
      scope = scope.where("LOWER(title) LIKE :q OR LOWER(COALESCE(description,'')) LIKE :q", q: like)
    end
    direction = @dir == "desc" ? :desc : :asc
    scope = case @sort
            when "follow_up_at" then scope.order(Arel.sql("follow_up_at #{direction} NULLS LAST"))
            when "created_at"   then scope.order(created_at: direction)
            when "title"        then scope.order(Arel.sql("LOWER(title) #{direction}"))
            else                     scope.by_urgency
            end
    @awaitings = scope
  end

  # #148: Kommunikation im Topic-Tab — Suche + Direction-Filter, Sort
  # (Datum/Absender/Betreff).
  def load_topic_communications_list
    @comm_direction = params[:direction].to_s.presence
    scope = @topic.communications
    scope = scope.where(direction: @comm_direction) if @comm_direction
    if @q
      like = "%#{@q.downcase}%"
      scope = scope.where("LOWER(subject) LIKE :q OR LOWER(COALESCE(sender, '')) LIKE :q OR LOWER(COALESCE(body_excerpt, '')) LIKE :q", q: like)
    end
    direction = @dir == "asc" ? :asc : :desc
    scope = case @sort
            when "sender"  then scope.order(Arel.sql("LOWER(COALESCE(sender, '')) #{direction}"), sent_at: :desc)
            when "subject" then scope.order(Arel.sql("LOWER(COALESCE(subject, '')) #{direction}"))
            else                scope.order(sent_at: direction)
            end
    @communications = scope
  end

  # #148: Wissen im Topic-Tab — Suche + Typ-Filter, Sort.
  def load_topic_knowledge_list
    @knowledge_item_type = params[:item_type].to_s.presence
    scope = @topic.knowledge_items.browsable   # #436/#932: Reply-KIs UND Personen/Orgs raus (eigene Reiter)
    scope = scope.where(item_type: @knowledge_item_type) if @knowledge_item_type
    if @q
      like = "%#{@q.downcase}%"
      scope = scope.where("LOWER(title) LIKE :q", q: like)
    end
    direction = @dir == "desc" ? :desc : :asc
    @knowledge_items = case @sort
                       when "file_updated_at" then scope.order(file_updated_at: direction)
                       when "file_created_at" then scope.order(file_created_at: direction)
                       when "item_type"       then scope.order(item_type: direction).order(:title)
                       else                        scope.order(Arel.sql("LOWER(title) #{direction}"))
                       end
    @initial_stack_items  = build_initial_stack
    @initial_stack_bodies = bodies_for_initial_stack(@initial_stack_items)
  end

  # #195: Personen-Reiter — Subset des Wissen-Tabs, fix auf
  # item_type=person. Nutzt denselben Stack-Layout.
  def load_topic_persons_list
    scope = @topic.knowledge_items.where(item_type: "person")
    if @q
      like = "%#{@q.downcase}%"
      scope = scope.where("LOWER(title) LIKE :q", q: like)
    end
    direction = @dir == "desc" ? :desc : :asc
    @persons_items = case @sort
                     when "file_updated_at" then scope.order(file_updated_at: direction)
                     when "file_created_at" then scope.order(file_created_at: direction)
                     else                        scope.order(Arel.sql("LOWER(title) #{direction}"))
                     end
    @initial_stack_items  = build_initial_stack
    @initial_stack_bodies = bodies_for_initial_stack(@initial_stack_items)
  end

  # #195: Quellen-Reiter — Sources, die als bib_source an mindestens
  # einem KI dieses Themas hängen. Split-Pane-Liste wie /sources, nur
  # gefiltert auf dieses Thema.
  def load_topic_sources_list
    # #155 Phase 5c: direkt mit dem Topic verknuepfte Recherche-Quellen
    # (mit Relevanz-Markierung) — getrennt von den ueber KIs zitierten.
    @research_source_topics = @topic.source_topics
                                    .includes(source: [:source_identifiers, :creator_kis])
                                    .order(Arel.sql(
                                      "CASE WHEN relevance = 'relevant' AND reached THEN 0 " \
                                      "WHEN relevance = 'relevant' THEN 1 ELSE 2 END"))
                                    .to_a
    source_ids = @topic.knowledge_items.where.not(bib_source_id: nil)
                        .distinct.pluck(:bib_source_id)
    scope = Source.where(id: source_ids).includes(:source_identifiers, :creator_kis)
    if @q
      like = "%#{@q.downcase}%"
      scope = scope.where("LOWER(title) LIKE :q OR LOWER(slug) LIKE :q", q: like)
    end
    direction = @dir == "desc" ? :desc : :asc
    @sources_items = case @sort
                     when "issued_date" then scope.order(issued_date: direction)
                     when "csl_type"    then scope.order(csl_type: direction).order(:title)
                     else                    scope.order(Arel.sql("LOWER(title) #{direction}"))
                     end
  end

  # Lädt @next_step_task / @open_tasks / @done_tasks für die Topic-Show.
  # Nur Root-Tasks (parent_id nil) als eigene Zeile; Unteraufgaben
  # werden eingerückt unter ihrer Eltern-Aufgabe angezeigt
  # (tasks/_row.html.erb mit Disclosure-Dreieck).
  def load_topic_show_lists
    @next_step_task = @topic.next_step_task

    # #148: Filter/Sort-Param-Auswertung — gleiche Konvention wie auf /tasks.
    @filter_priority    = params[:priority].to_s.strip.presence
    @filter_tag         = params[:tag].to_s.strip.presence
    # #215: Assignee-Filter analog zu TaskQuery#apply_assignee. Werte:
    #   nil/leer → Default: current_actor + unassigned (genau wie auf /tasks)
    #   "all"   → kein Filter
    #   "<id>"  → genau dieser Actor
    # Backward-compat: ?mine=1 wird auf assignee_id=<current_actor.id> gemappt.
    @filter_assignee_id = params[:assignee_id].to_s.strip.presence
    @filter_assignee_id = current_actor.id.to_s if @filter_assignee_id.blank? && @mine_only

    # #484 Toggle-Icons (Hans, 2026-06-03): tri-state Status-Toggle.
    #   open (default) | done | all — steuert, welche Listen geladen werden.
    # Der Assignee-Toggle nutzt @filter_assignee_id mit dem neuen Wert
    # "others" (= jemandem ANDEREN zugewiesen).
    @task_status = %w[open done all].include?(params[:task_status].to_s) ? params[:task_status].to_s : "open"
    @show_done   = @task_status != "open"

    if @task_status == "done"
      @open_tasks = Task.none
    else
      open_scope = @topic.ordered_tasks.includes(:assignee, :topics, :subtasks, :predecessors)
                         .where(tasks: { status: :open, parent_id: nil })
                         .where(task_topics: { next_step: false })
      open_scope = apply_topic_assignee_filter(open_scope)
      open_scope = open_scope.where("tasks.tags && ARRAY[?]::varchar[]", [@filter_tag]) if @filter_tag
      open_scope = open_scope.where(tasks: { priority: @filter_priority }) if @filter_priority && Task.priorities.key?(@filter_priority)
      if @q
        like = "%#{@q.downcase}%"
        open_scope = open_scope.where("LOWER(tasks.title) LIKE :q OR LOWER(COALESCE(tasks.description, '')) LIKE :q", q: like)
      end
      @open_tasks = apply_topic_task_sort(open_scope)
    end

    if @task_status == "open"
      @done_tasks = Task.none
    else
      done_scope = @topic.tasks.where(status: :done, parent_id: nil).order(completed_at: :desc)
      done_scope = apply_topic_assignee_filter(done_scope, key: :assignee_id)
      done_scope = done_scope.where("tasks.tags && ARRAY[?]::varchar[]", [@filter_tag]) if @filter_tag
      done_scope = done_scope.where(tasks: { priority: @filter_priority }) if @filter_priority && Task.priorities.key?(@filter_priority)
      @done_tasks = done_scope
    end
  end

  # Default-Verhalten wie auf /tasks (TaskQuery#apply_assignee):
  #   nil   → current_actor + unzugewiesen
  #   "all" → kein Filter
  #   "<id>"→ genau diese Actor-ID
  # key=:assignee_id, weil done_scope direkt auf tasks.assignee_id filtert
  # (kein JOIN-Alias), während open_scope tasks.assignee_id via includes hat.
  def apply_topic_assignee_filter(scope, key: nil)
    col = key ? key.to_s : "tasks.assignee_id"
    case @filter_assignee_id
    when nil
      scope.where("#{col} = ? OR #{col} IS NULL", current_actor.id)
    when "all"
      scope
    when "others"
      # #484 Toggle-Icons (Hans, 2026-06-03): jemandem ANDEREN zugewiesen.
      scope.where("#{col} IS NOT NULL AND #{col} <> ?", current_actor.id)
    else
      key ? scope.where(key => @filter_assignee_id) :
            scope.where(tasks: { assignee_id: @filter_assignee_id })
    end
  end

  # #148: nicht-default-Sortierungen für die Topic-Tasks-Liste. Default
  # `manual` (= task_topics.position) bleibt unangetastet.
  def apply_topic_task_sort(scope)
    return scope if @sort.blank? || @sort == "manual"
    direction = @dir == "desc" ? :desc : :asc
    case @sort
    when "title"      then scope.reorder(Arel.sql("LOWER(tasks.title) #{direction}"))
    when "priority"   then scope.reorder(priority: direction, due_date: :asc)
    when "due_date"   then scope.reorder(Arel.sql("tasks.due_date #{direction} NULLS LAST"))
    when "updated_at" then scope.reorder(updated_at: direction)
    else scope
    end
  end
end
