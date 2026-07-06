# #816: API für den geräteübergreifenden Stack-Verlauf. Strikt auf den
# eigenen Actor gescoped — Snapshots sind persönliche Arbeitsstände.
class StackSnapshotsController < ApplicationController
  skip_before_action :verify_authenticity_token

  # GET /stack_snapshots?key=knowledge.stack.history
  def index
    entries = StackSnapshot.for_bucket(current_actor, params[:key].to_s)
                           .order(pinned: :desc, saved_at: :desc)
    render json: { entries: entries.map(&:as_client_json) }
  end

  # POST /stack_snapshots — Write-Through eines Snapshots.
  def create
    snap = StackSnapshot.record!(
      actor: current_actor,
      history_key: params[:key].to_s,
      trail: Array(params[:trail]).map { |s| Array(s) },
      current: params[:current],
      pinned: params.key?(:pinned) ? ActiveModel::Type::Boolean.new.cast(params[:pinned]) : nil
    )
    render json: snap.as_client_json, status: :created
  rescue ArgumentError
    head :unprocessable_entity
  end

  # PATCH /stack_snapshots/:id — Pin togglen.
  def update
    snap = StackSnapshot.where(actor: current_actor).find(params[:id])
    snap.update!(pinned: ActiveModel::Type::Boolean.new.cast(params[:pinned]))
    StackSnapshot.trim!(current_actor, snap.history_key)
    render json: snap.as_client_json
  end

  # DELETE /stack_snapshots/:id
  def destroy
    StackSnapshot.where(actor: current_actor).find(params[:id]).destroy!
    head :no_content
  end

  private

  # Persönliche Verlaufs-Daten → Actor-Gate (wie ActorViews).
  def controller_resource_type        = "Actor"
  def controller_action_to_capability = action_name == "index" ? "read" : "update"
end
