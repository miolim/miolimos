module Api
  module V1
    # POST /api/v1/knowledge_items/:knowledge_item_uuid/replies — ein
    # Diskussion-Beitrag (Reply-KI) an einem KI. Das KI-Pendant zu
    # #task_comments. Reply-KIs sind eigenständige KIs (item_type=:reply,
    # parent_type="KnowledgeItem", parent_uuid=<parent.uuid>); sie erben
    # die Topics des Parents, damit sie im selben Diskussions-Tab landen.
    #
    # #460 (Hans, 2026-06-04): Ergänzt, damit ein API-Agent den roten
    # Faden einer Aktivität führen kann — bislang ging das nur im Web.
    class KnowledgeRepliesController < BaseController
      REPLY_SERIALIZER = ->(r) do
        {
          id:           r.uuid,
          parent_uuid:  r.parent_uuid,
          actor_id:     r.creator_id,
          actor_name:   r.creator&.name,
          body:         r.body,
          created_at:   r.published_at || r.created_at
        }
      end

      def create
        parent = KnowledgeItem.find(params[:knowledge_item_uuid])
        body   = params.require(:body).to_s.strip

        # FileProxy.create verlangt einen Title (slugifiziert die Datei).
        # Platzhalter + nachträglich nullen — analog KnowledgeReplies-
        # Controller#create / TaskComments#create.
        placeholder = "Reply #{Time.current.strftime('%Y%m%d-%H%M%S')}"
        reply = FileProxy.create(
          actor:     current_actor,
          title:     placeholder,
          item_type: :reply,
          content:   body
        )
        reply.update!(
          title:        nil,
          parent_type:  "KnowledgeItem",
          parent_uuid:  parent.uuid,
          published_at: Time.current
        )
        parent.topics.each do |topic|
          reply.knowledge_item_topics.find_or_create_by!(topic: topic)
        end
        # #518 (Hans, 2026-06-05): @-erwähnte Agenten anstupsen.
        BuilderInboxPoke.poke_mentioned_agents(
          reply, except: current_actor,
          note: "Antwort an Dich in KI „#{parent.title}“"
        )

        render json: { data: REPLY_SERIALIZER.call(reply) }, status: :created
      end

      private

      # Beiträge hängen an einem KI — Capability-Check geht auf die
      # KnowledgeItem-Resource (wer create-Recht auf KIs hat, darf
      # kommentieren).
      def controller_resource_type
        "KnowledgeItem"
      end
    end
  end
end
