module Api
  module V1
    # #155 Phase 5-Vorbereitung (Schritt 1): API-Zugriff auf typed
    # Wikilink-Relations. Der Researcher-Agent schreibt die Synthese mit
    # `[[Ziel ^anchor]]`-Wikilinks; RelationSync legt die Relation-Rows
    # an. Ueber diese Endpunkte liest/pflegt der Agent dann Label,
    # Beschreibung, Richtung und Provenance.
    #
    #   GET   /api/v1/knowledge_items/:knowledge_item_uuid/relations
    #   GET   /api/v1/knowledge_items/:knowledge_item_uuid/relations/:anchor_id
    #   PATCH /api/v1/knowledge_items/:knowledge_item_uuid/relations/:anchor_id
    class RelationsController < BaseController
      before_action :load_source
      before_action :load_relation, only: [:show, :update]

      SERIALIZER = ->(rel) {
        {
          anchor_id:       rel.anchor_id,
          source_uuid:     rel.source_uuid,
          source_type:     rel.source_type,
          target_uuid:     rel.target_uuid,
          target_type:     rel.target_type,
          target_title:    target_title_for(rel),
          label:           rel.label,
          description:     rel.description,
          direction:       rel.direction,
          ebene:           ebene_for(rel),
          recognized_by:   rel.recognized_by&.name,
          recognized_role: rel.recognized_role,
          recognized_via:  rel.recognized_via,
          recognized_at:   rel.recognized_at,
          orphaned_at:     rel.orphaned_at
        }
      }

      def self.target_title_for(rel)
        return rel.target_uuid unless rel.target_type == "KnowledgeItem"
        KnowledgeItem.find_by(uuid: rel.target_uuid)&.title || rel.target_uuid
      end

      def self.ebene_for(rel)
        return nil if rel.label.blank?
        RelationType.find_by_label(rel.label)&.ebene
      end

      def index
        scope = Relation.for_source(@source.uuid).order(:anchor_id)
        scope = scope.active   if params[:status] == "active"
        scope = scope.orphaned if params[:status] == "orphaned"
        render_collection(scope, serializer: SERIALIZER)
      end

      def show
        render_one(@relation, serializer: SERIALIZER)
      end

      def update
        @relation.assign_attributes(permitted_attrs)
        @relation.recognized_by ||= current_actor
        @relation.recognized_at ||= Time.current
        @relation.save!
        render_one(@relation, serializer: SERIALIZER)
      end

      private

      def load_source
        @source = KnowledgeItem.find_by!(uuid: params[:knowledge_item_uuid])
      end

      def load_relation
        @relation = Relation.find_by!(source_uuid: @source.uuid,
                                      anchor_id: params[:anchor_id])
      end

      def permitted_attrs
        params.require(:relation).permit(:label, :description, :direction,
                                         :recognized_role, :recognized_via)
      end

      # Beziehungen sind Metadaten zu KnowledgeItems — Gate gegen KI.
      def controller_resource_type
        "KnowledgeItem"
      end

      def controller_action_to_capability
        case action_name
        when "update" then "update"
        else               "read"
        end
      end
    end
  end
end
