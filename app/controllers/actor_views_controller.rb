# #160: User-History — POST-Endpoint, an den der view-tracker-Stimulus-
# Controller die View-Pings schickt. Antwort hält sich klein (JSON ok)
# damit der sendBeacon-Pfad schnell zurückkommt.
class ActorViewsController < ApplicationController
  # Tracker-POSTs sind low-stakes (eigener Actor stempelt eigene Views).
  # CSRF-Skip erlaubt sendBeacon ohne separate Token-Holerei beim
  # Page-Unload.
  skip_before_action :verify_authenticity_token, only: [:create]

  def create
    type = params[:viewable_type].to_s
    unless ActorView::TRACKABLE_TYPES.include?(type)
      head :unprocessable_entity and return
    end

    # #160 Phase 5: viewable_id ist seit der Mixed-PK-Migration ein
    # String — Task/Topic/Source/Awaiting senden int-Strings, Knowledge-
    # Item sendet UUIDs.
    id = params[:viewable_id].to_s.strip
    head :unprocessable_entity and return if id.blank?

    view = ActorView.upsert_for!(
      actor:         current_actor,
      viewable_type: type,
      viewable_id:   id,
      duration_ms:   params[:duration_ms].to_i,
      was_edited:    ActiveModel::Type::Boolean.new.cast(params[:was_edited]) || false,
      session_token: params[:session_token].presence
    )
    render json: { id: view.id, duration_ms: view.duration_ms, was_edited: view.was_edited }
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private

  # ActorView ist eine Self-Service-Resource — jeder authentifizierte
  # Actor darf seine eigenen Views stempeln. Wir hängen die Capability
  # an "Actor" (read/update), nicht an die jeweilige Entität.
  def controller_resource_type
    "Actor"
  end

  def controller_action_to_capability
    "update"
  end
end
