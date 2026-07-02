module Api
  module V1
    class CommunicationTopicsController < BaseController
      def create
        comm  = Communication.find(params[:communication_id])
        topic = Topic.find(params.require(:topic_id))
        CommunicationTopic.find_or_create_by!(communication: comm, topic: topic)

        render json: { data: { communication_id: comm.id, topic_id: topic.id } }, status: :created
      end

      def destroy
        comm  = Communication.find(params[:communication_id])
        topic = Topic.find(params[:id])
        link  = CommunicationTopic.find_by!(communication: comm, topic: topic)
        link.destroy!
        head :no_content
      end

      private

      def controller_resource_type
        "Communication"
      end

      def controller_action_to_capability
        "update"
      end
    end
  end
end
