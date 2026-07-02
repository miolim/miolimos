# #384 Phase 3b (Hans, 2026-05-27): Reply-KI-Endpoint fuer
# Dialog-Beitraege an einer Task. Analog KnowledgeRepliesController,
# nur fuer Task-Eltern. Reply-KIs: item_type=:reply,
# parent_type=„Task", parent_id_int=<task.id>.
class TaskRepliesController < ApplicationController
  before_action :set_parent_task

  skip_before_action :verify_authenticity_token, only: [:create, :update, :destroy]

  # GET /tasks/:task_id/replies
  # #232 (Hans, 2026-06-01): Liefert NUR das Replies-Listen-Frame-Fragment
  # (tasks/_replies_list, in einen turbo-frame gewickelt). Wird von Turbo
  # nachgeladen, wenn ein Reply-Live-Broadcast den Frame zum Reload anstoesst —
  # gerendert mit dem current_actor DIESER Session (viewer-korrekt).
  def index
    render partial: "tasks/replies_list", locals: { task: @parent_task }
  end

  # POST /tasks/:task_id/replies
  # Body-Param: body (Markdown), optional draft (true|false).
  def create
    body  = params[:body].to_s
    draft = ActiveModel::Type::Boolean.new.cast(params[:draft])
    placeholder = "Reply #{Time.current.strftime('%Y%m%d-%H%M%S')}"
    reply = FileProxy.create(
      actor:     current_actor,
      title:     placeholder,
      item_type: :reply,
      content:   body
    )
    reply.update!(
      title:         nil,
      parent_type:   "Task",
      parent_id_int: @parent_task.id,
      published_at:  draft ? nil : Time.current
    )
    # Topic-Vererbung: Reply uebernimmt die Topics der Task,
    # damit es im Topic-Diskussions-Tab des Topics auftaucht.
    @parent_task.topics.each do |topic|
      reply.knowledge_item_topics.find_or_create_by!(topic: topic)
    end
    # #382 (Hans, 2026-06-03): veroeffentlichte Antwort auf eine Agenten-
    # Aufgabe -> den Agenten direkt anstupsen (Entwuerfe nicht, eigene
    # Antworten des Agenten nicht).
    if !draft && (agent = @parent_task.assignee).is_a?(AgentActor) && agent != current_actor
      BuilderInboxPoke.poke(actor: agent, note: "Neue Antwort auf Aufgabe ##{@parent_task.id}")
    end
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace(
          "task_replies_#{@parent_task.id}",
          partial: "tasks/replies_section",
          # #451 (Hans, 2026-06-01): nach Entwurf-Save den Compose
          # refokussieren, damit ein direkt folgendes Strg+Umschalt+Enter
          # (Entwurf veroeffentlichen) einen Tastatur-Fokus hat.
          locals:  { task: @parent_task, focus_compose: draft }
        )
      end
      format.html { redirect_to task_path(@parent_task) }
    end
  end

  # PATCH /tasks/:task_id/replies/:id
  def update
    reply = KnowledgeItem.replies.find_by(uuid: params[:id])
    raise ActiveRecord::RecordNotFound unless reply
    unless reply.editable_by?(current_actor)
      head :forbidden and return
    end
    new_body = params[:body]
    if new_body.present?
      FileProxy.update(actor: current_actor, knowledge_item: reply, content: new_body)
    end
    if ActiveModel::Type::Boolean.new.cast(params[:publish]) && reply.published_at.nil?
      reply.update!(published_at: Time.current)
      # #382: Entwurf-Antwort veroeffentlicht -> Agenten-Assignee anstupsen.
      if (agent = @parent_task.assignee).is_a?(AgentActor) && agent != current_actor
        BuilderInboxPoke.poke(actor: agent, note: "Neue Antwort auf Aufgabe ##{@parent_task.id}")
      end
    end
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace(
          "task_replies_#{@parent_task.id}",
          partial: "tasks/replies_section",
          locals:  { task: @parent_task }
        )
      end
      format.html { redirect_to task_path(@parent_task) }
    end
  end

  # DELETE /tasks/:task_id/replies/:id
  # #384 Phase 3d (Hans, 2026-05-27): Eigene letzte Reply loeschen.
  # editable_by? prueft „nur eigene, nur solange keine fremde Folge-
  # Reply existiert" — identische Regel wie fuer Edit.
  def destroy
    reply = KnowledgeItem.replies.find_by(uuid: params[:id])
    raise ActiveRecord::RecordNotFound unless reply
    # #536: Löschen eigener Beiträge immer erlaubt (deletable_by?), auch
    # nach fremder Folge-Antwort — anders als Bearbeiten.
    unless reply.deletable_by?(current_actor)
      head :forbidden and return
    end
    reply.destroy!
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace(
          "task_replies_#{@parent_task.id}",
          partial: "tasks/replies_section",
          locals:  { task: @parent_task }
        )
      end
      format.html { redirect_to task_path(@parent_task) }
    end
  end

  private

  def set_parent_task
    @parent_task = Task.find(params[:task_id])
  end

  def controller_resource_type        = "Task"
  # #232: index ist ein reiner Lese-Zugriff (Listen-Fragment), Rest braucht update.
  def controller_action_to_capability = action_name == "index" ? "read" : "update"
end
