# Manueller Inbox-Trigger für AgentActors. Hans klickt einen Button im
# Dashboard → wir stempeln `actors.inbox_run_requested_at = now`. Der
# Builder liest das Flag im Heartbeat-Endpoint und macht im nächsten
# Cron-Tick (≤10min während Arbeitszeit) einen Inbox-Lauf.
class BuilderTriggersController < ApplicationController
  def create
    actor = AgentActor.find(params[:id])
    # #382 (Hans, 2026-06-03): Flag setzen + tmux-Send laufen jetzt im
    # gemeinsamen BuilderInboxPoke-Service (denselben Pfad nutzt auch das
    # automatische Anstupsen bei Publish/Antwort). Der Button feuert IMMER
    # (debounce: false).
    # #512 (Hans, 2026-06-04): `clear=1` → /clear vor dem Prompt (frischer Kontext).
    clear = ActiveModel::Type::Boolean.new.cast(params[:clear])
    BuilderInboxPoke.poke(actor: actor, debounce: false, clear: clear)

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: helpers.toast_stream(
          message: clear ? "Inbox-Lauf (frischer Kontext) für #{actor.name} angefordert." \
                         : "Inbox-Lauf für #{actor.name} angefordert."
        )
      end
      format.html { redirect_back fallback_location: dashboard_path,
                                  notice: "Inbox-Lauf angefordert." }
    end
  end

  private

  # Trigger ist ein Update auf den Builder-Actor — Capability-Check
  # läuft auf Actor.update.
  def controller_resource_type
    "Actor"
  end

  def controller_action_to_capability
    "update"
  end
end
