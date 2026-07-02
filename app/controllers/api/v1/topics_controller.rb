module Api
  module V1
    class TopicsController < BaseController
      TOPIC_SERIALIZER = ->(t) do
        {
          id: t.id, name: t.name, slug: t.slug, description: t.description,
          status: t.status, color: t.color, template: t.template,
          team_id: t.team_id, creator_id: t.creator_id,
          created_at: t.created_at, updated_at: t.updated_at
        }
      end

      def index
        scope = visible(Topic)
        scope = scope.where(status: params[:status])       if params[:status].present?
        scope = scope.where(template: ActiveModel::Type::Boolean.new.cast(params[:template])) if params.key?(:template)
        scope = scope.where(team_id: params[:team_id])     if params[:team_id].present?
        render_collection(scope.order(:id), serializer: TOPIC_SERIALIZER)
      end

      def show
        render_one(visible(Topic).find(params[:id]), serializer: TOPIC_SERIALIZER)
      end

      def create
        topic = Topic.create!(permitted_attrs.merge(creator: current_actor))
        render_one(topic, serializer: TOPIC_SERIALIZER, status: :created)
      end

      def update
        topic = Topic.find(params[:id])
        topic.update!(permitted_attrs)
        render_one(topic, serializer: TOPIC_SERIALIZER)
      end

      def instantiate
        template = Topic.find(params[:id])
        new_topic = TopicTemplateService.instantiate(
          template,
          new_name: params.require(:new_name),
          creator:  current_actor,
          team_id:  params[:team_id]
        )
        render_one(new_topic, serializer: TOPIC_SERIALIZER, status: :created)
      rescue TopicTemplateService::NotATemplateError => e
        render json: { error: e.message, code: "not_a_template" }, status: :unprocessable_entity
      end

      private

      def controller_action_to_capability
        return "create" if action_name == "instantiate"
        super
      end

      def permitted_attrs
        params.permit(:name, :slug, :description, :status, :color, :template, :team_id)
      end
    end
  end
end
