module Api
  module V1
    class CommunicationsController < BaseController
      COMM_SERIALIZER = ->(c) do
        {
          id: c.id, type: c.type, subject: c.subject, body: c.body,
          sent_at: c.sent_at, direction: c.direction, external_id: c.external_id,
          oauth_credential_id: c.oauth_credential_id,
          created_at: c.created_at, updated_at: c.updated_at
        }
      end

      def index
        scope = visible(Communication)
        scope = scope.where(direction: params[:direction]) if params[:direction].present?
        if params[:topic_id].present?
          scope = scope.joins(:communication_topics).where(communication_topics: { topic_id: params[:topic_id] })
        end
        if params[:mentioned_uuid].present?
          scope = scope.joins(:communication_mentions)
                       .where(communication_mentions: { mentioned_uuid: params[:mentioned_uuid] })
        end
        if params[:oauth_credential_id].present?
          scope = scope.where(oauth_credential_id: params[:oauth_credential_id])
        end
        render_collection(scope.order(sent_at: :desc, id: :desc), serializer: COMM_SERIALIZER)
      end

      def show
        render_one(Communication.find(params[:id]), serializer: COMM_SERIALIZER)
      end
    end
  end
end
