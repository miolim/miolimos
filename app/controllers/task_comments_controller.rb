# Kommentar-Thread an einem Task. Beide Actor-Typen (Hans + Agents
# wie miolim_builder) nutzen denselben Endpoint, jeweils als
# eingeloggter Actor. Antwort als Turbo-Stream, der den Thread und
# das Form-Reset auf der Task-Detail-Seite aktualisiert.
class TaskCommentsController < ApplicationController
  before_action :set_task
  before_action :set_comment, only: [:show, :edit, :update, :destroy, :publish]
  before_action :enforce_editable!, only: [:edit, :update, :destroy]

  def create
    body = params[:body].to_s.strip
    if body.blank?
      respond_to do |format|
        format.turbo_stream { render turbo_stream: helpers.toast_stream(message: "Kommentar leer.") }
        format.html { redirect_to task_path(@task), alert: "Kommentar leer." }
      end
      return
    end
    # #167: zwei Submit-Buttons im Form, "as_draft=1" schaltet auf Entwurf.
    # Sonst sofort veröffentlicht.
    published = params[:as_draft].to_s == "1" ? nil : Time.current
    @comment = @task.comments.create!(actor: current_actor, body: body, published_at: published)
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: [
          turbo_stream.append("task_comments_#{@task.id}",
            partial: "task_comments/comment", locals: { comment: @comment }),
          turbo_stream.replace("task_comment_form_#{@task.id}",
            partial: "task_comments/form", locals: { task: @task })
        ]
      end
      format.html { redirect_to task_path(@task) }
    end
  end

  # POST /tasks/:task_id/comments/:id/publish — Entwurf zum live-Kommentar
  # machen. Setzt published_at und tauscht die Comment-Row im Stream.
  def publish
    @comment.publish!
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace("task_comment_#{@comment.id}",
          partial: "task_comments/comment", locals: { comment: @comment })
      end
      format.html { redirect_to task_path(@task) }
    end
  end

  # GET /tasks/:task_id/comments/:id — Body-Frame neu rendern (nach Cancel).
  def show
    render partial: "task_comments/body_frame", locals: { comment: @comment }
  end

  # GET /tasks/:task_id/comments/:id/edit — Edit-Form in den Body-Frame.
  def edit
    render partial: "task_comments/edit_form", locals: { comment: @comment }
  end

  # PATCH /tasks/:task_id/comments/:id — Body aktualisieren, Frame ersetzen.
  def update
    new_body = params[:body].to_s.strip
    if new_body.blank?
      render turbo_stream: helpers.toast_stream(message: "Kommentar darf nicht leer sein.")
      return
    end
    @comment.update!(body: new_body)
    render partial: "task_comments/body_frame", locals: { comment: @comment }
  end

  # DELETE /tasks/:task_id/comments/:id — Comment entfernen, Row im Stream.
  def destroy
    @comment.destroy!
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.remove("task_comment_#{@comment.id}")
      end
      format.html { redirect_to task_path(@task) }
    end
  end

  private

  def set_task
    @task = Task.find(params[:task_id])
  end

  def set_comment
    @comment = @task.comments.find(params[:id])
  end

  def enforce_editable!
    return if @comment.editable_by?(current_actor)
    render json: { error: "Nicht editierbar" }, status: :forbidden
  end

  def controller_resource_type
    "Task"
  end

  def controller_action_to_capability
    return "update" if action_name.in?(%w[edit update publish])
    return "delete" if action_name == "destroy"
    return "read"   if action_name == "show"
    super
  end
end
