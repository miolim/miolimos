# #162: Web-UI nested controller: /tasks/:task_id/tags. Anders als
# TaskTopics ist `tags` keine eigene Tabelle, sondern eine string[]-
# Spalte auf tasks. Add/Remove sind also schlichte Array-Operationen
# mit Normalisierung (downcase + strip).
class TaskTagsController < ApplicationController
  before_action :set_task

  # POST /tasks/:task_id/tags
  # Akzeptiert `tag_id=<existierender>` ODER `create_with=<neuer>`.
  # Wir behandeln beide identisch — Tags sind freie Strings, nicht
  # referentielle Entities. Normalisierung: strip + downcase.
  def create
    tag = (params[:tag_id].presence || params[:create_with].presence).to_s.strip.downcase
    if tag.empty?
      head :unprocessable_entity and return
    end
    current_tags = Array(@task.tags).map(&:to_s).map(&:downcase)
    unless current_tags.include?(tag)
      @task.update!(tags: current_tags + [tag])
    end
    render_chips
  end

  # DELETE /tasks/:task_id/tags/:tag — :tag ist URL-encoded das Tag-
  # Wort selbst. Idempotent: entfernt-aus-Array.
  def destroy
    target = params[:tag].to_s.strip.downcase
    remaining = Array(@task.tags).map(&:to_s).map(&:downcase).reject { |t| t == target }
    if remaining != Array(@task.tags)
      @task.update!(tags: remaining)
    end
    render_chips
  end

  private

  def set_task
    @task = Task.find(params[:task_id])
  end

  def render_chips
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace(
          "task_tags_chips_#{@task.id}",
          partial: "tasks/tags_chips",
          locals:  { task: @task }
        )
      end
      format.json { render json: { ok: true, tags: @task.tags } }
      format.html { redirect_back fallback_location: task_path(@task) }
    end
  end

  def controller_resource_type
    "Task"
  end

  def controller_action_to_capability
    # Beide Aktionen schreiben auf task.tags — update reicht.
    "update"
  end
end
