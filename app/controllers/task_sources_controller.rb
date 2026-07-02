# Web-UI nested controller: /tasks/:task_id/sources
# Chip-basierte Source-Zuordnung — analog zu task_topics, ohne
# Position oder Next-Step. Quick-Create lehnen wir ab: Sources
# brauchen csl_type + Metadaten, das Anlegen gehört nach /sources.
class TaskSourcesController < ApplicationController
  def create
    task   = Task.find(params[:task_id])
    source = Source.find_by(slug: params[:source_id]) ||
             Source.find_by(id: params[:source_id])

    TaskSource.find_or_create_by!(task: task, source: source) if source

    respond_with_chips(task)
  end

  def destroy
    task   = Task.find(params[:task_id])
    source = Source.find_by(slug: params[:id]) || Source.find_by(id: params[:id])
    TaskSource.find_by(task: task, source: source)&.destroy
    @unlinked_source = source

    respond_with_chips(task)
  end

  private

  def respond_with_chips(task)
    task.reload
    streams = [
      turbo_stream.replace("task_sources_chips_#{task.id}",
        partial: "tasks/sources_chips", locals: { task: task })
    ]
    if action_name == "destroy" && @unlinked_source
      streams << helpers.toast_stream(
        message:  "Quelle '#{@unlinked_source.title}' entfernt",
        undo_url: task_sources_path(task),
        undo_payload: { source_id: @unlinked_source.slug }
      )
    end
    respond_to do |format|
      format.turbo_stream { render turbo_stream: streams }
      format.json { render json: { ok: true } }
      format.html { redirect_back fallback_location: task_path(task) }
    end
  end

  def controller_resource_type
    "Task"
  end

  def controller_action_to_capability
    "update"
  end
end
