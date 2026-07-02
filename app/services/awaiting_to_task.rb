# Transaktion: Awaiting → Task. Wird genau einmal aufgerufen,
# wenn aus einem Wartepunkt echte Arbeit wird.
#
#   1. Neuer Task (open) mit Titel, Creator, communication-Vererbung
#   2. Topics vom Awaiting kopieren (mit Position im jeweiligen Topic)
#   3. Contact vom Awaiting kopieren (falls gesetzt)
#   4. Falls Awaiting.task gesetzt: TaskDependency auf diesen Auslöser-Task
#      (Awaiting selbst ist kein Task, kann nicht in task_dependencies stehen)
#   5. Awaiting auflösen mit Note
#
# Kapselt bisher dupliziertes Wissen in AwaitingsController (web + API).
class AwaitingToTask
  def self.call(awaiting:, creator:, title:)
    new_task = nil
    Awaiting.transaction do
      new_task = Task.create!(
        title:            title,
        status:           :open,
        creator:          creator,
        assignee_id:      creator.id,
        communication_id: awaiting.communication_id
      )

      awaiting.topics.each do |topic|
        position = (topic.task_topics.maximum(:position) || 0) + 1
        TaskTopic.create!(task: new_task, topic: topic, position: position)
      end

      if awaiting.contact_uuid
        TaskMention.find_or_create_by!(task: new_task, mentioned_uuid: awaiting.contact_uuid)
      end

      if awaiting.task_id
        TaskDependency.create!(predecessor_id: awaiting.task_id,
                               successor: new_task,
                               dependency_type: :finish_to_start)
      end

      awaiting.resolve!(note: "Aufgabe erstellt: #{new_task.title}")
    end
    new_task
  end
end
