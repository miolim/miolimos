module Api
  module V1
    # POST /api/v1/heartbeat — der Caller markiert sich selbst als
    # "lebendig" (setzt actors.last_seen_at = now). Der miolim_builder
    # ruft den Endpoint zu jedem Inbox-Tick auf, damit das Dashboard
    # einen Aktivitäts-Indikator anzeigen kann.
    #
    # GET /api/v1/heartbeat — gibt Status aller AgentActors mit
    # last_seen_at zurück (für das Dashboard, oder für einen externen
    # Watchdog-Cron, der bei Stille Hans benachrichtigt).
    class HeartbeatsController < BaseController
      def create
        # Pending-Trigger erkennen, BEVOR wir last_seen_at stempeln —
        # sonst würden wir den Trigger genau in dem Moment "konsumieren",
        # bevor wir ihn dem Caller mitteilen können.
        requested_at = current_actor.inbox_run_requested_at
        pending = requested_at.present? &&
                  (current_actor.last_seen_at.nil? || requested_at > current_actor.last_seen_at)

        current_actor.update!(last_seen_at: Time.current)
        # Pending-Trigger nach erfolgreichem Heartbeat zurücksetzen,
        # damit der nächste Tick nicht noch einmal als "manuell
        # angefordert" gilt.
        current_actor.update!(inbox_run_requested_at: nil) if pending

        render json: {
          data: { actor_id: current_actor.id, last_seen_at: current_actor.last_seen_at },
          # #167: Counter zählt nur veröffentlichte Aufgaben — sonst
          # würde ein Entwurf des Auftraggebers den Agent unruhig stimmen.
          open_tasks: Task.published.open.where(assignee_id: current_actor.id).count,
          # #518 (Hans, 2026-06-05): offene KI-Diskussions-Mentions (Antworten
          # AN den Agenten in KIs, unbeantwortet). GET /api/v1/mentions listet sie.
          pending_mentions: AgentMentions.count_for(current_actor),
          pending_trigger: pending,
          triggered_at: pending ? requested_at : nil
        }
      end

      # GET /api/v1/mentions — die offenen KI-Mentions des Callers.
      # #587: auch Body-Mentions in normalen KIs (kind != "reply") —
      # dort ist das KI selbst der Thread (parent_uuid = eigene uuid),
      # eine Antwort darauf gilt als Beantwortung.
      def mentions
        items = AgentMentions.pending_for(current_actor).map do |r|
          reply  = r.item_type == "reply"
          parent = reply ? KnowledgeItem.find_by(uuid: r.parent_uuid) : r
          { reply_uuid: r.uuid, kind: r.item_type,
            parent_uuid: parent&.uuid, parent_title: parent&.title,
            author: r.creator&.name, created_at: r.published_at || r.created_at,
            body: r.body }
        end
        render json: { data: items }
      end

      def show
        agents = AgentActor.where(active: true).where.not(last_seen_at: nil).order(:name)
        render json: {
          data: agents.map { |a|
            {
              actor_id: a.id, name: a.name,
              last_seen_at: a.last_seen_at,
              age_seconds: (Time.current - a.last_seen_at).to_i,
              inbox_run_requested_at: a.inbox_run_requested_at
            }
          }
        }
      end

      private

      # Heartbeat ist Self-Service: lesen darf jeder authentifizierte
      # Actor (Stufe „read" auf Actor); schreiben darf ebenfalls jeder
      # authentifizierte Actor — er darf ja nur sich selbst stempeln.
      def controller_resource_type
        "Actor"
      end

      def controller_action_to_capability
        return "read"   if action_name.in?(%w[show mentions])
        return "update" if action_name == "create"
        super
      end
    end
  end
end
