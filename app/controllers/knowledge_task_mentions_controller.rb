# Web-UI nested controller: /knowledge_items/:uuid/task_mentions
# Spiegel zum task_mentions_controller — der User kann auch von der
# KI-Seite aus eine Task verknüpfen oder eine neue Task quick-erfassen,
# die direkt mit dieser KI verbunden ist. Schreibt in dieselbe
# `task_mentions`-Tabelle.
class KnowledgeTaskMentionsController < ApplicationController
  def create
    item = KnowledgeItem.find_by!(uuid: params[:knowledge_item_uuid])
    task = resolve_task(item)

    TaskMention.find_or_create_by!(task: task, mentioned_uuid: item.uuid) if task

    respond_with_chips(item)
  end

  def destroy
    item = KnowledgeItem.find_by!(uuid: params[:knowledge_item_uuid])
    task = Task.find_by(id: params[:id])
    TaskMention.find_by(task_id: task&.id, mentioned_uuid: item.uuid)&.destroy
    @unlinked_task = task

    respond_with_chips(item)
  end

  private

  # Picker schickt entweder task_id (existierende Task) oder create_with
  # (Quick-Create: neue Task mit dem eingegebenen Titel + sofort an die
  # KI gebunden). Schickt die Task an Current.actor (siehe Task-Model
  # before_validation).
  # #173: Quick-Create-Task erbt die Topics der KI — Hans erfasst hier
  # offensichtlich eine Aufgabe IM Kontext dieses KIs, also auch im
  # Kontext seiner Themen.
  def resolve_task(item)
    if (text = params[:create_with].to_s.strip).present?
      Task.transaction do
        t = Task.create!(title: text, creator: current_actor)
        item.topics.each do |topic|
          position = (topic.task_topics.maximum(:position) || 0) + 1
          TaskTopic.create!(task: t, topic: topic, position: position)
        end
        t
      end
    else
      raw = params.require(:task_id)
      Task.find_by(id: raw)
    end
  end

  def respond_with_chips(item)
    item.reload
    streams = [
      turbo_stream.replace("ki_task_mentions_chips_#{item.uuid}",
        partial: "knowledge_items/task_mentions_chips", locals: { item: item })
    ]
    if action_name == "destroy" && @unlinked_task
      streams << helpers.toast_stream(
        message:  "Aufgabe '#{@unlinked_task.title.truncate(40)}' aus Verknüpfungen entfernt",
        undo_url: knowledge_item_task_mentions_path(item),
        undo_payload: { task_id: @unlinked_task.id }
      )
    end
    respond_to do |format|
      format.turbo_stream { render turbo_stream: streams }
      format.html { redirect_back fallback_location: knowledge_item_path(item.uuid) }
    end
  end

  def controller_resource_type
    "KnowledgeItem"
  end

  def controller_action_to_capability
    "update"
  end
end
