# Web-UI nested controller: /tasks/:task_id/subtasks
# Picker-getriebene Unteraufgaben-Verwaltung.
#   - child_id   → existierende Task wird unter parent gehängt (parent_id setzen)
#   - create_with → neue Task wird mit Titel + parent_id angelegt
class TaskSubtasksController < ApplicationController
  def create
    parent = Task.find(params[:task_id])
    child  = resolve_child(parent)

    respond_with_chips(parent, child)
  rescue ActiveRecord::RecordInvalid => e
    respond_with_chips(parent, nil, alert: e.message)
  end

  def destroy
    parent = Task.find(params[:task_id])
    child  = parent.subtasks.find(params[:id])
    child.update!(parent_id: nil)
    @unlinked_child = child

    respond_with_chips(parent, child)
  end

  private

  def resolve_child(parent)
    child = if (text = params[:create_with].to_s.strip).present?
              Task.create!(title: text, creator: current_actor, parent: parent)
            else
              raw = params.require(:child_id)
              task = Task.find(raw)
              task.update!(parent_id: parent.id)
              task
            end
    inherit_parent_topics(child, parent)
    child
  end

  # Subtask erbt einmalig die Topics ihres Parents — Snapshot beim
  # Anlegen, keine Live-Propagation. Damit kann die Subtask in einer
  # Topic-Aufgabenliste auftauchen / als next_step gewählt werden, ohne
  # dass spätere Topic-Änderungen am Parent automatisch durchschlagen
  # (das würde die Subtask schnell unübersichtlich verteilen).
  def inherit_parent_topics(child, parent)
    parent.topics.each do |topic|
      TaskTopic.find_or_create_by!(task: child, topic: topic)
    end
  end

  def respond_with_chips(parent, _child, alert: nil)
    parent.reload
    streams = [
      turbo_stream.replace("task_subtasks_chips_#{parent.id}",
        partial: "tasks/subtasks_chips", locals: { task: parent })
    ]
    if action_name == "destroy" && @unlinked_child
      streams << helpers.toast_stream(
        message:  "'#{@unlinked_child.title.truncate(40)}' aus Unteraufgaben entfernt",
        undo_url: task_subtasks_path(parent),
        undo_payload: { child_id: @unlinked_child.id }
      )
    end
    respond_to do |format|
      format.turbo_stream { render turbo_stream: streams }
      format.html { redirect_to task_path(parent), alert: alert }
    end
  end

  def controller_resource_type
    "Task"
  end

  def controller_action_to_capability
    action_name == "create" ? "create" : "update"
  end
end
