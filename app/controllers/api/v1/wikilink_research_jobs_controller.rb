module Api
  module V1
    # #183: API-Endpoint für den Researcher-Agenten, damit er nach Anlage
    # der recherchierten KI den Job mit `target_knowledge_item_id`
    # verknüpfen kann — danach rendert das Wikilink-Frontend den Treffer
    # als grünen Anker (statt ⏳).
    class WikilinkResearchJobsController < BaseController
      def update
        job = WikilinkResearchJob.find(params[:id])
        attrs = params.permit(:target_knowledge_item_id)
        job.update!(attrs)
        render json: {
          id: job.id,
          source_knowledge_item_id: job.source_knowledge_item_id,
          target_title:             job.target_title,
          target_source_url:        job.target_source_url,
          target_knowledge_item_id: job.target_knowledge_item_id,
          task_id:                  job.task_id
        }
      end

      private

      def controller_resource_type
        "KnowledgeItem"
      end

      def controller_action_to_capability
        "update"
      end
    end
  end
end
