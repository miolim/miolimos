module Api
  module V1
    class TaskTopicsController < BaseController
      # Nested under /api/v1/tasks/:task_id/topics
      # Business-Ressource ist Task (wir editieren eine Task-Assoziation),
      # also prüft AccessGate gegen "Task", nicht gegen "TaskTopic".
      def create
        task  = Task.find(params[:task_id])
        topic = Topic.find(params.require(:topic_id))
        position = params[:position].presence&.to_i || next_position_for(topic)

        link = TaskTopic.find_or_initialize_by(task: task, topic: topic)
        link.position = position
        link.save!

        render json: { data: { task_id: task.id, topic_id: topic.id, position: link.position } },
               status: :created
      end

      def destroy
        task  = Task.find(params[:task_id])
        topic = Topic.find(params[:id])
        link  = TaskTopic.find_by!(task: task, topic: topic)
        link.destroy!
        head :no_content
      end

      private

      def controller_resource_type
        "Task"
      end

      def controller_action_to_capability
        case action_name
        when "destroy" then "update"
        else "update"
        end
      end

      def next_position_for(topic)
        (topic.task_topics.maximum(:position) || 0) + 1
      end
    end
  end
end
