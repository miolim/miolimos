module Api
  module V1
    # #155 Phase 5c: der Researcher verknuepft eine Quelle mit einem
    # Recherche-Topic und markiert sie. #575 (Hans, 2026-06-10): zwei
    # Dimensionen — relevance (relevant/irrelevant) + reached (bool).
    # Legacy-Wert relevance=unreached wird weiter angenommen und auf
    # relevant + reached=false abgebildet (Modell-Setter).
    # Nested unter /api/v1/sources/:source_slug/topics.
    #
    #   GET    .../topics            — Liste der Topic-Links der Quelle
    #   POST   .../topics            — Link anlegen ({topic_id, relevance?, reached?, note?})
    #   PATCH  .../topics/:id        — Markierung/Note aendern (:id = topic_id)
    #   DELETE .../topics/:id        — Link entfernen
    class SourceTopicsController < BaseController
      before_action :load_source

      SERIALIZER = ->(st) {
        {
          source_slug: st.source.slug,
          topic_id:    st.topic_id,
          topic_slug:  st.topic.slug,
          relevance:   st.relevance,
          reached:     st.reached,
          note:        st.note
        }
      }

      def index
        links = @source.source_topics.includes(:topic, :source)
        render json: { data: links.map { |st| SERIALIZER.call(st) } }
      end

      def create
        topic = Topic.find(params.require(:topic_id))
        st = SourceTopic.find_or_initialize_by(source: @source, topic: topic)
        st.relevance = params[:relevance].presence || st.relevance || "relevant"
        st.reached   = ActiveModel::Type::Boolean.new.cast(params[:reached]) if params.key?(:reached)
        st.note      = params[:note] if params.key?(:note)
        st.save!
        render_one(st, serializer: SERIALIZER, status: :created)
      end

      def update
        st = @source.source_topics.find_by!(topic_id: params[:id])
        st.relevance = params[:relevance] if params.key?(:relevance)
        st.reached   = ActiveModel::Type::Boolean.new.cast(params[:reached]) if params.key?(:reached)
        st.note      = params[:note]      if params.key?(:note)
        st.save!
        render_one(st, serializer: SERIALIZER)
      end

      def destroy
        st = @source.source_topics.find_by!(topic_id: params[:id])
        st.destroy!
        head :no_content
      end

      private

      def load_source
        @source = Source.find_by!(slug: params[:source_slug])
      end

      # Wir editieren eine Source-Assoziation → Gate gegen "Source".
      def controller_resource_type
        "Source"
      end

      def controller_action_to_capability
        case action_name
        when "index" then "read"
        when "create" then "create"
        when "destroy" then "delete"
        else "update"
        end
      end
    end
  end
end
