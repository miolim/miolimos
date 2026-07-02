# #378 Phase 3 (Hans, 2026-05-26): Highlight-Wrap-Action aus
# KnowledgeItemsController ausgelagert. Endpoint bleibt unter
# `POST /knowledge_items/:uuid/wrap_highlight` (route :to-Mapping).
#
# Service-Aufruf bleibt unveraendert; nur der Controller-Container
# wechselt, damit knowledge_items_controller schmaler wird.
class KnowledgeHighlightsController < ApplicationController
  before_action :set_item

  skip_before_action :verify_authenticity_token, only: [:wrap, :wrap_person]

  # POST /knowledge_items/:uuid/wrap_highlight
  # Params:
  #   anchor         — block-N oder ^stable-id der Ziel-Sektion
  #   color          — gelb|rot|gruen|blau|lila ODER "keine" (unwrap)
  #   selected_text  — optional Substring innerhalb des Blocks; wenn
  #                    gesetzt, nur den Substring wrappen.
  def wrap
    # #469 (Hans, 2026-06-02): Instanz statt .call, damit wir den beim
    # Wrap gesetzten Anker zurueckgeben koennen — das Selektions-Menue
    # haengt darauf praezise Link/Kommentar/Aufgabe.
    wrapper = BodyHighlightWrapper.new(
      item:          @item,
      actor:         current_actor,
      anchor:        params.require(:anchor),
      color:         params.require(:color),
      selected_text: params[:selected_text]
    )
    wrapper.call
    render json: { ok: true, anchor: wrapper.result_anchor }
  rescue BodyHighlightWrapper::Error => e
    render json: { error: e.message }, status: :unprocessable_content
  end

  # #655: Selektion als Personen-Wikilink auszeichnen ([[@Name]]).
  # POST /knowledge_items/:uuid/wrap_person — anchor + selected_text.
  def wrap_person
    BodyPersonWrapper.call(
      item:          @item,
      actor:         current_actor,
      anchor:        params.require(:anchor),
      selected_text: params.require(:selected_text)
    )
    render json: { ok: true }
  rescue BodyPersonWrapper::Error => e
    render json: { error: e.message }, status: :unprocessable_content
  end

  private

  def set_item
    @item = KnowledgeItem.find(params[:knowledge_item_uuid] || params[:uuid])
  end

  def controller_resource_type        = "KnowledgeItem"
  def controller_action_to_capability = "update"
end
