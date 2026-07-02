# #203 Phase E.2: Member-Actions aus TasksController in einen Concern
# ausgelagert. Die Actions teilen alle dasselbe Pattern:
#   1. eine Task-Operation (toggle_done!, publish!, set_commitment, ...)
#   2. eine Stream-Replacement-Antwort + Toast
#   3. ein HTML-Redirect-Fallback
#
# Inkludiert von TasksController; nutzt dort definierte Helfer
# (@task, topic_context, record_edit_view).
module TaskMemberActions
  extend ActiveSupport::Concern

  # #480 Increment 2 (Hans, 2026-06-03): Highlight in der Task-Description —
  # dieselbe Markdown-Flaeche wie im KI-Body. BodyHighlightWrapper operiert
  # ueber read_body/write_body jetzt auch auf der `description`-Spalte.
  # Antwort wie bei der KI-Variante: JSON mit dem gesetzten Anker. Das
  # Frontend laedt danach die Task-Card neu (Highlight erscheint).
  def wrap_highlight
    wrapper = BodyHighlightWrapper.new(
      item:          @task,
      actor:         current_actor,
      anchor:        params.require(:anchor),
      color:         params.require(:color),
      selected_text: params[:selected_text]
    )
    wrapper.call
    render json: { ok: true, anchor: wrapper.result_anchor }
  rescue BodyHighlightWrapper::Error => e
    render json: { error: e.message }, status: :unprocessable_content
  end

  # #655: Selektion in der Task-Description als Personen-Wikilink.
  def wrap_person
    BodyPersonWrapper.call(
      item:          @task,
      actor:         current_actor,
      anchor:        params.require(:anchor),
      selected_text: params.require(:selected_text)
    )
    render json: { ok: true }
  rescue BodyPersonWrapper::Error => e
    render json: { error: e.message }, status: :unprocessable_content
  end

  # #480 Increment 3 (Hans, 2026-06-03): Absatz-Aktionen an der Task-
  # Description — wie im KI-Body (KnowledgeAnchorsController), nur dass der
  # Markdown in `tasks.description` liegt. Anker werden via TaskAnchor
  # indiziert, sodass `[[^anker]]`-Wikilinks global auf den Task-Absatz
  # aufloesen. Frontend: paragraph_actions_controller.js (surface=task).

  # Idempotent: stellt sicher, dass ein Block einen stabilen `^id` hat.
  def ensure_anchor
    anchor = resolve_task_anchor(params.require(:anchor).to_s)
    render json: { anchor: anchor }
  rescue ArgumentError => e
    render json: { error: e.message }, status: :unprocessable_content
  end

  # Kommentar-KI an einem Task-Absatz. Body traegt einen Anker-only-
  # Wikilink zurueck auf den Absatz; der Resolver loest ihn ueber TaskAnchor
  # auf die Aufgabe auf. Antwort: UUID des neuen KI (Stack haengt die Card an).
  def comment_at
    anchor  = resolve_task_anchor(params.require(:anchor).to_s)
    snippet = task_block_anchor.text_at(anchor)
    words   = snippet.split(/\s+/).first(4).join(" ").presence || @task.title
    comment = FileProxy.create(
      actor:     current_actor,
      title:     "Kommentar zu: #{words}".truncate(120),
      item_type: :comment,
      content:   "[[^#{anchor}|↳ #{@task.title}]]\n\n",
      topics:    [], contacts: [], tags: ["kommentar"]
    )
    render json: { uuid: comment.uuid, anchor: anchor }
  rescue ArgumentError => e
    render json: { error: e.message }, status: :unprocessable_content
  end

  # Aufgabe an einem Task-Absatz. Beschreibung der neuen Aufgabe traegt den
  # Anker-only-Wikilink zurueck. Titel = markierter Text (Frontend) oder
  # Default. Antwort: task_id (Stack haengt die Card an). reply immer false.
  def task_at
    anchor = resolve_task_anchor(params.require(:anchor).to_s)
    title  = params[:title].to_s.strip.presence || "Aufgabe zu: #{@task.title}"
    task   = Task.create!(
      title:       title.truncate(120),
      description: "[[^#{anchor}|↳ #{@task.title}]]",
      creator:     current_actor
    )
    render json: { task_id: task.id, reply: false }
  rescue ArgumentError => e
    render json: { error: e.message }, status: :unprocessable_content
  end

  # "Warte auf Ergebnis" — erstellt einen Awaiting-Eintrag,
  # referenziert den Task als Ausloeser, uebernimmt Topics & ersten Kontakt.
  def create_awaiting
    awaiting = Awaiting.new(
      creator:      current_actor,
      task:         @task,
      title:        params[:description].presence || params[:title].presence ||
                    "Ergebnis von: #{@task.title}",
      description:  params[:notes],
      follow_up_at: parse_date(params[:follow_up_at]) || (Date.today + 7),
      contact_ki:   @task.mentioned_kis.first
    )
    Awaiting.transaction do
      awaiting.save!
      @task.topics.each do |topic|
        AwaitingTopic.find_or_create_by!(awaiting: awaiting, topic: topic)
      end
    end
    redirect_to awaiting_path(awaiting), notice: "Wartepunkt angelegt"
  rescue ActiveRecord::RecordInvalid => e
    redirect_to task_path(@task), alert: e.message
  end

  # Asana-style: Task in eine andere Sektion ziehen — setzt commitment.
  # param commitment: "inbox" | "today" | "soon" | "later"
  def set_commitment
    previous = @task.commitment
    target = params[:commitment].to_s
    new_value = target == "inbox" ? nil : target.presence
    @task.update!(commitment: new_value) if Task.commitments.key?(new_value) || new_value.nil?
    record_edit_view(@task)

    respond_to do |format|
      format.turbo_stream do
        streams = [
          # #737 (Hans): blade_kind/blade_id mitgeben, sonst fällt der
          # Plus-Button (Append-an-Stack) beim Wann-Wechsel aus der Row —
          # gleiches Muster wie #286 (update) und #235 (create).
          turbo_stream.replace_all("#task_row_#{@task.id}",
            partial: "tasks/row",
            locals:  { task: @task, topic: @task.topics.first, show_topic: true,
                       blade_kind: "task", blade_id: @task.id })
        ]
        unless params[:undo].present?
          label = { "today" => "Heute", "soon" => "Demnächst", "later" => "Später" }[new_value] || "Eingang"
          streams << helpers.toast_stream(
            message:  "Verschoben nach '#{label}'",
            undo_url: set_commitment_task_path(@task),
            undo_payload: { commitment: previous || "inbox", undo: "1" }
          )
        end
        render turbo_stream: streams
      end
      format.html { redirect_to tasks_path }
    end
  end

  # #167: Entwurfs-Aufgabe veroeffentlichen. Macht den Datensatz fuer
  # den Assignee (Agent oder andere User) sichtbar.
  # #310: Wenn ein description-Param mitgesendet wird (capture-description-
  # Stimulus-Controller liest das Textarea-Value vor dem Submit aus),
  # wird die Description vor dem publish! aktualisiert — sonst geht
  # frisch-getippter Text verloren, weil der Description-Blur-Submit
  # innerhalb derselben Card unterdrueckt ist (#294).
  def publish
    # #397 (Hans, 2026-05-28): NIE die gespeicherte Beschreibung mit
    # einem leeren Form-Param ueberschreiben. Wenn capture-description
    # aus irgendeinem Grund nicht firet (z.B. weil das versteckte Feld
    # der Publish-Form noch den initialen Server-Wert traegt und
    # zwischenzeitlich via Blur-Submit eine neuere Description in der
    # DB gelandet ist), wuerde der alte Wert die neue Description
    # ueberschreiben. Update nur, wenn der Param NICHT leer ist.
    incoming = params[:description].to_s
    if incoming.present? && incoming != @task.description.to_s
      @task.update!(description: incoming)
    end
    @task.publish!
    # #382 (Hans, 2026-06-03): Wenn Hans eine Aufgabe an einen Agenten
    # veroeffentlicht, den Agenten direkt anstupsen (statt nur auf den
    # naechsten Cron-Tick zu warten). Kein Selbst-Poke (agent != actor).
    notify_assignee_agent("Aufgabe ##{@task.id} veröffentlicht: #{@task.title}")
    topic = topic_context
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: [
          # #163: Detail-Refresh ueber den inneren `task_<id>`-Div statt
          # ueber das `task_detail`-Frame. Der Div liegt sowohl im Frame
          # (Legacy-Pages) als auch direkt in der Blade-Card — der
          # Stream trifft also beide Page-Typen.
          turbo_stream.replace_all("#task_#{@task.id}",
            partial: "tasks/detail_body", locals: { task: @task }),
          # #756: Status-Icon in der Card-Toolbar live austauschen (globe →
          # pause) — es liegt außerhalb von #task_<id>.
          turbo_stream.replace_all("#task_status_control_#{@task.id}",
            partial: "tasks/status_control", locals: { task: @task }),
          turbo_stream.replace_all("#task_row_#{@task.id}",
            partial: "tasks/row", locals: { task: @task, topic: topic }),
          helpers.toast_stream(message: "Aufgabe veröffentlicht.")
        ]
      end
      format.html { redirect_to task_path(@task) }
    end
  end

  # #411 (Hans, 2026-05-30): Symmetrisches Gegenstueck zu publish —
  # Aufgabe zurueck in den Entwurfsmodus (= pausieren). Hans schreibt
  # das offiziell dem Creator zu: "bei allen Aufgaben, die man einem
  # anderen zugewiesen hat". Wir lassen jeden mit `update`-Capability
  # darauf rauf, was dem bisherigen Berechtigungsmodell entspricht
  # (publish ist ebenfalls update).
  def unpublish
    @task.unpublish!
    topic = topic_context
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: [
          turbo_stream.replace_all("#task_#{@task.id}",
            partial: "tasks/detail_body", locals: { task: @task }),
          # #756: Status-Icon in der Card-Toolbar live austauschen (pause →
          # globe) — es liegt außerhalb von #task_<id>.
          turbo_stream.replace_all("#task_status_control_#{@task.id}",
            partial: "tasks/status_control", locals: { task: @task }),
          turbo_stream.replace_all("#task_row_#{@task.id}",
            partial: "tasks/row", locals: { task: @task, topic: topic }),
          helpers.toast_stream(message: "Aufgabe pausiert.")
        ]
      end
      format.html { redirect_to task_path(@task) }
    end
  end

  def toggle_done
    @task.toggle_done!
    record_edit_view(@task)
    topic = topic_context
    respond_to do |format|
      format.turbo_stream do
        streams = [
          turbo_stream.replace_all("#task_row_#{@task.id}",
            partial: "tasks/row", locals: { task: @task, topic: topic }),
          # #163: siehe publish — Detail-Refresh ueber inneren Div.
          turbo_stream.replace_all("#task_#{@task.id}",
            partial: "tasks/detail_body", locals: { task: @task })
        ]
        unless params[:undo].present?
          msg = @task.done? ? "Aufgabe erledigt" : "Aufgabe wieder offen"
          streams << helpers.toast_stream(
            message:  msg,
            undo_url: toggle_done_task_path(@task, topic_slug: topic&.slug),
            undo_payload: { undo: "1" }
          )
        end
        render turbo_stream: streams
      end
      format.html do
        if topic
          redirect_to topic_path(topic)
        else
          redirect_back fallback_location: tasks_path
        end
      end
    end
  end

  # #150 Phase B: Task → neues Topic. Subtasks/Mentions/Wartepunkte
  # transferieren, Original-Task als done mit Verweis schliessen.
  def promote_to_topic
    topic = TaskToTopicPromoter.call(@task, actor: current_actor)
    redirect_to topic_path(topic),
                notice: "Aufgabe in Thema „#{topic.name}\" umgewandelt."
  rescue ActiveRecord::RecordInvalid => e
    redirect_back fallback_location: task_path(@task),
                  alert: "Umwandlung fehlgeschlagen: #{e.message}"
  end

  private

  # #382 (Hans, 2026-06-03): Builder-Actor anstupsen, wenn die Aufgabe
  # einem Agenten gehoert und nicht der Agent selbst die Aktion ausloest.
  def notify_assignee_agent(note)
    agent = @task.assignee
    return unless agent.is_a?(AgentActor) && agent != current_actor
    BuilderInboxPoke.poke(actor: agent, note: note)
  end

  # #480 Inc.3: KnowledgeBlockAnchor ist seit dieser Aenderung task-aware
  # (liest/schreibt die `description`-Spalte). Wir nutzen ihn fuer
  # ensure!/text_at an der Task-Description.
  def task_block_anchor
    @task_block_anchor ||= KnowledgeBlockAnchor.new(@task, actor: current_actor)
  end

  # `block-N` (DOM-Index) -> stabiler `^id`, idempotent. Bestehende stabile
  # Anker werden unveraendert durchgereicht. Wirft bei N ausserhalb.
  def resolve_task_anchor(requested)
    if requested.start_with?("block-") && (n = requested.sub("block-", "").to_i) > 0
      anchor = task_block_anchor.ensure!(n)
      raise ArgumentError, "Block-Index #{n} außerhalb" if anchor.nil?
      anchor
    else
      requested
    end
  end
end
