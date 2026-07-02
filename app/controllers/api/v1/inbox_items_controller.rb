module Api
  module V1
    class InboxItemsController < BaseController
      ITEM_SERIALIZER = ->(i) {
        {
          id: i.id, source_kind: i.source_kind, source_url: i.source_url,
          title: i.title, status: i.status, processor_kind: i.processor_kind,
          created_at: i.created_at, processed_at: i.processed_at,
          result: i.result
        }
      }

      def index
        scope = InboxItem.active.order(created_at: :desc)
        scope = scope.where(status: params[:status]) if params[:status].present?
        render_collection(scope, serializer: ITEM_SERIALIZER)
      end

      def show
        render_one(InboxItem.find(params[:id]), serializer: ITEM_SERIALIZER)
      end

      # Eingangspunkt für externe Clients (Browser-Add-on etc.). Akzeptiert
      # source_url und optional title/raw_content; rät source_kind, wenn
      # nicht gesetzt.
      def create
        attrs = permitted_attrs
        attrs[:source_kind] ||= guess_source_kind(attrs)
        attrs[:status]      ||= "pending"
        item = InboxItem.create!(attrs.merge(creator: current_actor))

        # #171 Phase 4: optionale topic_ids (Slugs oder IDs) — Browser-
        # Add-on kann das Thema gleich mitgeben, der Processor vererbt
        # es später an die erzeugten KIs/Tasks.
        attach_topics!(item)

        # Optional: sofort verarbeiten, wenn `auto: true` und ein
        # passender Processor verfügbar ist.
        if ActiveModel::Type::Boolean.new.cast(params[:auto]) &&
           (kind = item.suggested_processor_kind)
          klass = Inbox::Registry.find(kind)
          klass&.run(item, actor: current_actor)
          item.reload
        end

        render_one(item, serializer: ITEM_SERIALIZER, status: :created)
      end

      private

      def permitted_attrs
        params.permit(:source_kind, :source_url, :raw_content, :external_path,
                      :title, payload: {}).to_h.symbolize_keys
      end

      def guess_source_kind(attrs)
        if attrs[:source_url].present?
          Inbox::Processors::YoutubeTranscribe.youtube_url?(attrs[:source_url]) ? "youtube_url" : "web_url"
        elsif attrs[:raw_content].present?
          "markdown"
        else
          "text"
        end
      end

      # #171 Phase 4: liest topic_ids (Slug oder ID) aus den Params und
      # hängt sie an das InboxItem. Idempotent, unbekannte IDs/Slugs
      # werden stillschweigend übergangen — der Caller will den Import
      # nicht wegen eines Tippfehlers im Topic-Namen verlieren.
      def attach_topics!(item)
        raw = Array(params[:topic_ids]).map { |s| s.to_s.strip }.reject(&:blank?)
        return if raw.empty?
        raw.each do |id|
          topic = Topic.find_by(slug: id) || Topic.find_by(id: id.to_i)
          next unless topic
          InboxItemTopic.find_or_create_by!(inbox_item: item, topic: topic)
        end
      end
    end
  end
end
