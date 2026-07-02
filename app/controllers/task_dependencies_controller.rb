# Nested unter Task: /tasks/:task_id/dependencies
# Verwaltet Predecessor-Kanten (wer blockiert DIESE Aufgabe).
# Zyklus-/Self-/Duplikat-Checks sitzen im Model.
class TaskDependenciesController < ApplicationController
  def create
    task        = Task.find(params[:task_id])
    predecessor = Task.find(params.require(:predecessor_id))

    TaskDependency.create!(
      predecessor:     predecessor,
      successor:       task,
      dependency_type: :finish_to_start
    )
    respond_with_task(task)
  rescue ActiveRecord::RecordInvalid => e
    respond_with_task(task, alert: e.message)
  end

  def destroy
    task = Task.find(params[:task_id])
    dep  = TaskDependency.find(params[:id])
    @unlinked_predecessor = dep.predecessor
    dep.destroy!
    respond_with_task(task)
  end

  private

  def respond_with_task(task, alert: nil)
    task.reload
    streams = [
      turbo_stream.replace("task_dependencies_chips_#{task.id}",
        partial: "tasks/dependencies_chips", locals: { task: task })
    ]
    if action_name == "destroy" && @unlinked_predecessor
      streams << helpers.toast_stream(
        message:  "Blockade durch '#{@unlinked_predecessor.title.truncate(40)}' aufgehoben",
        undo_url: task_dependencies_path(task),
        undo_payload: { predecessor_id: @unlinked_predecessor.id }
      )
    end
    respond_to do |format|
      format.turbo_stream { render turbo_stream: streams }
      format.html { redirect_to task_path(task), alert: alert }
    end
  end

  def controller_resource_type
    "Task"
  end

  def controller_action_to_capability
    "update"
  end
end
