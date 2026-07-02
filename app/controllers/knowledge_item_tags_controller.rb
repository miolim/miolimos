# #363 (Hans, 2026-05-25): KI-Tags-Picker. Analog TaskTagsController —
# Tags sind eine string[]-Spalte auf knowledge_items, kein
# referentielles Entity. Add/Remove sind Array-Operationen mit
# Normalisierung (strip + downcase).
class KnowledgeItemTagsController < ApplicationController
  before_action :set_item

  # POST /knowledge_items/:knowledge_item_uuid/tags
  def create
    tag = (params[:tag_id].presence || params[:create_with].presence).to_s.strip.downcase
    if tag.empty?
      head :unprocessable_entity and return
    end
    current_tags = Array(@item.tags).map(&:to_s).map(&:downcase)
    unless current_tags.include?(tag)
      @item.update!(tags: current_tags + [tag])
    end
    render_chips
  end

  # DELETE /knowledge_items/:knowledge_item_uuid/tags/:tag
  def destroy
    target = params[:tag].to_s.strip.downcase
    remaining = Array(@item.tags).map(&:to_s).map(&:downcase).reject { |t| t == target }
    if remaining != Array(@item.tags)
      @item.update!(tags: remaining)
    end
    render_chips
  end

  private

  def set_item
    @item = KnowledgeItem.find_by!(uuid: params[:knowledge_item_uuid])
  end

  def render_chips
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace(
          "knowledge_tags_chips_#{@item.uuid}",
          partial: "knowledge_items/tags_chips",
          locals:  { item: @item }
        )
      end
      format.json { render json: { ok: true, tags: @item.tags } }
      format.html { redirect_back fallback_location: knowledge_item_path(@item.uuid) }
    end
  end

  def controller_resource_type      = "KnowledgeItem"
  def controller_action_to_capability = "update"
end
