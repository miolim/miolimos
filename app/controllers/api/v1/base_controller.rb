module Api
  module V1
    class BaseController < ActionController::API
      include Gated

      # Authentication must run BEFORE Gated's enforce_access_gate, otherwise
      # the gate receives a nil current_actor and blows up on actor.id.
      prepend_before_action :authenticate_actor

      rescue_from AccessGate::Unauthorized do |e|
        render json: { error: e.message, code: "forbidden" }, status: :forbidden
      end

      rescue_from ActiveRecord::RecordNotFound do
        render json: { error: "Not found", code: "not_found" }, status: :not_found
      end

      rescue_from ActiveRecord::RecordInvalid do |e|
        render json: { error: e.record.errors.full_messages.join(", "), code: "invalid" },
               status: :unprocessable_entity
      end

      private

      def authenticate_actor
        token = request.headers["Authorization"]&.split("Bearer ", 2)&.last
        # #1052: DB hält nur SHA256-Digests — reinkommendes Token hashen
        # und über den Unique-Index vergleichen.
        @current_actor = Actor.find_by(api_token_digest: Actor.digest_api_token(token), active: true) if token.present?
        unless @current_actor
          render json: { error: "Unauthorized", code: "invalid_token" }, status: :unauthorized
          return
        end
        Current.actor = @current_actor
      end

      def current_actor
        @current_actor
      end

      # #602 S2: Agent-on-behalf-of (Confused-Deputy-Schutz). Bearbeitet
      # ein Agent die Anfrage eines Nicht-Admin-Nutzers, hängt er
      # ?on_behalf_of=<actor_id> an LESE-Aufrufe — die Antwort ist dann
      # auf DESSEN Sichtbarkeit gefiltert: der Agent gibt nie mehr preis,
      # als der Anfragende selbst sehen dürfte. Ohne Param bleibt die
      # volle Sicht des API-Actors (Bestand; Agenten/Admins sind exempt).
      # Konvention fürs Agenten-Verhalten: miolimOS - Operations-API.
      def visibility_actor
        return @visibility_actor if defined?(@visibility_actor)
        @visibility_actor =
          if params[:on_behalf_of].present?
            HumanActor.active.find(params[:on_behalf_of])
          else
            current_actor
          end
      end

      def visible(model)
        model.visible_to(visibility_actor)
      end

      # ─── Pagination / Response helpers ───────────────────────────────────

      MAX_PER_PAGE = 100

      def paginate(relation)
        page     = [params[:page].to_i, 1].max
        per_page = params[:per_page].to_i
        per_page = 25 if per_page <= 0
        per_page = MAX_PER_PAGE if per_page > MAX_PER_PAGE

        total = relation.count(:all)
        rows  = relation.offset((page - 1) * per_page).limit(per_page)

        [rows, { total: total, page: page, per_page: per_page }]
      end

      def render_collection(relation, serializer:)
        rows, meta = paginate(relation)
        render json: { data: rows.map { |r| serializer.call(r) }, meta: meta }
      end

      def render_one(record, serializer:, status: :ok)
        render json: { data: serializer.call(record) }, status: status
      end
    end
  end
end
