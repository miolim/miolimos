module Api
  module V1
    # Personen/Orgs sind seit Phase 2 KIs. Der alte Endpunkt antwortet
    # mit 410 Gone statt einem 404, damit Clients erkennen, dass der
    # Endpunkt bewusst entfernt wurde.
    class ContactsController < BaseController
      skip_before_action :authenticate_actor!, only: :gone, raise: false

      def gone
        render json: {
          error: "Gone. Use /api/v1/knowledge_items?type=person|organization."
        }, status: :gone
      end
    end
  end
end
