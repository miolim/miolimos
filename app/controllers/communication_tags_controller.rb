# #695 (Hans): Web-UI nested controller /communications/:communication_id/tags.
# `tags` ist eine string[]-Spalte auf communications (kein Join) — Add/Remove
# sind Array-Operationen mit Normalisierung (downcase + strip). Spiegelt
# TaskTagsController.
class CommunicationTagsController < ApplicationController
  before_action :set_communication

  # POST /communications/:communication_id/tags — tag_id ODER create_with.
  def create
    tag = (params[:tag_id].presence || params[:create_with].presence).to_s.strip.downcase
    if tag.empty?
      head :unprocessable_entity and return
    end
    current_tags = Array(@communication.tags).map(&:to_s).map(&:downcase)
    @communication.update!(tags: current_tags + [tag]) unless current_tags.include?(tag)
    render_chips
  end

  # DELETE /communications/:communication_id/tags/:tag (URL-encoded Tag-Wort).
  def destroy
    target    = params[:tag].to_s.strip.downcase
    remaining = Array(@communication.tags).map(&:to_s).map(&:downcase).reject { |t| t == target }
    @communication.update!(tags: remaining) if remaining != Array(@communication.tags)
    render_chips
  end

  private

  def set_communication
    @communication = Communication.find(params[:communication_id])
  end

  def render_chips
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace(
          "comm_tags_chips_#{@communication.id}",
          partial: "communications/tags_chips",
          locals:  { comm: @communication }
        )
      end
      format.json { render json: { ok: true, tags: @communication.tags } }
      format.html { redirect_back fallback_location: communication_path(@communication) }
    end
  end

  def controller_resource_type        = "Communication"
  def controller_action_to_capability = "update"
end
