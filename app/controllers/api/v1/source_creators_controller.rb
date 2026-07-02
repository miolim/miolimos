module Api
  module V1
    # #516 (Hans, 2026-06-05): Autor-Verknüpfung (Quelle↔Person) pflegen —
    # identifizieren (provisorisch → identifiziert mit Konfidenz/Provenienz)
    # und umhängen (Split: auf eine andere Person zeigen lassen).
    #
    #   PATCH /api/v1/sources/:source_slug/creators/:id
    #     person_uuid?   → auf eine andere Person umhängen (Split)
    #     identification? (provisional|identified)
    #     confidence?    (vermutet|wahrscheinlich|bestätigt)
    #     identified_via? (z.B. orcid, name, affiliation)
    class SourceCreatorsController < BaseController
      def update
        source = Source.find_by!(slug: params[:source_slug])
        sc     = source.source_creators.find(params[:id])

        if params[:person_uuid].present?
          person = KnowledgeItem.find_by(uuid: params[:person_uuid].to_s)
          raise ActiveRecord::RecordNotFound, "person not found" unless person
          sc.knowledge_item_uuid = person.uuid
        end

        sc.identification = params[:identification] if params.key?(:identification)
        sc.confidence     = params[:confidence]     if params.key?(:confidence)
        sc.identified_via = params[:identified_via] if params.key?(:identified_via)
        if sc.identification == "identified"
          sc.identified_by ||= current_actor
          sc.identified_at ||= Time.current
        end
        sc.save!

        render json: { data: serialize(sc) }
      end

      private

      def serialize(sc)
        person = sc.knowledge_item
        {
          id:             sc.id,
          source_slug:    sc.source.slug,
          person_uuid:    sc.knowledge_item_uuid,
          person_title:   person&.title,
          role:           sc.role,
          identification: sc.identification,
          confidence:     sc.confidence,
          identified_via: sc.identified_via
        }
      end

      def controller_resource_type
        "Source"
      end
    end
  end
end
