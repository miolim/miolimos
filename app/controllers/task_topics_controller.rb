# Web-UI nested controller: /tasks/:task_id/topics
# Chip-basierte Topic-Zuordnung + Positions-Update für Drag-and-Drop.
class TaskTopicsController < ApplicationController
  include NestedTopicAssignment

  nested_topic_config parent_class: Task,
                      join_class:   TaskTopic,
                      id_param:     :task_id,
                      with_position: true

  private

  def on_success(task)
    task.reload
    streams = [
      # Detail-Panel: Topic-Chips
      turbo_stream.replace("task_topics_chips_#{task.id}",
        partial: "tasks/topics_chips", locals: { task: task }),
      # Liste links / Dashboard: Row neu rendern, damit der Topic-
      # Marker am Anfang aktuell ist. Wenn die Row im DOM nicht
      # vorhanden ist (z.B. /tasks/:id Vollbild ohne Liste), ignoriert
      # Turbo den Replace stillschweigend — kein Schaden.
      turbo_stream.replace("task_row_#{task.id}",
        partial: "tasks/row",
        locals:  { task: task, topic: task.topics.first, show_topic: true })
    ]
    if action_name == "destroy" && @unlinked_topic
      streams << helpers.toast_stream(
        message:  "Thema '#{@unlinked_topic.name}' entfernt",
        undo_url: task_topics_path(task),
        undo_payload: { topic_id: @unlinked_topic.slug }
      )
    end
    respond_to do |format|
      format.turbo_stream { render turbo_stream: streams }
      format.json { render json: { ok: true } }
      format.html { redirect_back fallback_location: task_path(task) }
    end
  end
end
