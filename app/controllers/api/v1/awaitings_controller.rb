module Api
  module V1
    class AwaitingsController < BaseController
      AWAITING_SERIALIZER = ->(a) do
        {
          id: a.id,
          title: a.title,
          description: a.description,
          status: a.status,
          follow_up_at: a.follow_up_at,
          resolved_at: a.resolved_at,
          resolution_note: a.resolution_note,
          creator_id: a.creator_id,
          contact_uuid: a.contact_uuid,
          communication_id: a.communication_id,
          task_id: a.task_id,
          topic_ids: a.topics.pluck(:id),
          created_at: a.created_at,
          updated_at: a.updated_at
        }
      end

      def index
        scope = visible(Awaiting).includes(:topics)
        scope = scope.where(status: params[:status])                           if params[:status].present?
        scope = scope.where("follow_up_at < ?", Date.today)                    if ActiveModel::Type::Boolean.new.cast(params[:overdue])
        scope = scope.where(contact_uuid: params[:contact_uuid])                   if params[:contact_uuid].present?
        if params[:topic_id].present?
          scope = scope.joins(:awaiting_topics).where(awaiting_topics: { topic_id: params[:topic_id] })
        end
        scope = scope.by_urgency
        render_collection(scope, serializer: AWAITING_SERIALIZER)
      end

      def show
        render_one(Awaiting.find(params[:id]), serializer: AWAITING_SERIALIZER)
      end

      def create
        awaiting = nil
        Awaiting.transaction do
          awaiting = Awaiting.create!(permitted_attrs.merge(creator: current_actor))
          topic_ids = Array(params[:topic_ids]).map(&:to_i).reject(&:zero?)
          awaiting.topics = Topic.where(id: topic_ids).to_a if topic_ids.any?
        end
        render_one(awaiting, serializer: AWAITING_SERIALIZER, status: :created)
      end

      def update
        awaiting = Awaiting.find(params[:id])
        Awaiting.transaction do
          awaiting.update!(permitted_attrs)
          if params.key?(:topic_ids)
            topic_ids = Array(params[:topic_ids]).map(&:to_i).reject(&:zero?)
            awaiting.topics = Topic.where(id: topic_ids).to_a
          end
        end
        render_one(awaiting, serializer: AWAITING_SERIALIZER)
      end

      def destroy
        Awaiting.find(params[:id]).destroy!
        head :no_content
      end

      def resolve
        awaiting = Awaiting.find(params[:id])
        awaiting.resolve!(note: params[:resolution_note].presence)
        render_one(awaiting, serializer: AWAITING_SERIALIZER)
      end

      # Transaktion in AwaitingToTask. Antwort: task + aufgelöstes awaiting.
      def create_task
        awaiting = Awaiting.find(params[:id])
        title = params[:title].presence || "Folgeaufgabe: #{awaiting.title.truncate(40)}"
        new_task = AwaitingToTask.call(awaiting: awaiting, creator: current_actor, title: title)
        render json: { data: {
          task:     Api::V1::TasksController::TASK_SERIALIZER.call(new_task),
          awaiting: AWAITING_SERIALIZER.call(awaiting.reload)
        }}, status: :created
      end

      private

      def controller_action_to_capability
        return "update" if action_name == "resolve"
        return "create" if action_name == "create_task"
        super
      end

      def controller_resource_type
        return "Task" if action_name == "create_task"
        super
      end

      def permitted_attrs
        params.permit(:title, :description, :status, :follow_up_at,
                      :resolved_at, :resolution_note,
                      :contact_uuid, :communication_id, :task_id)
      end
    end
  end
end
