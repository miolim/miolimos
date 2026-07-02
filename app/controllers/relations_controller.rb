# #239 Phase B: Endpoints fuer typed Wikilink-Relations. URL-Pfad:
# /knowledge_items/:source_uuid/relations/:anchor_id
# #239 Phase B+: zusaetzlich Auto-Typify-Endpoint, der einen untyped
# Wikilink in einen typed verwandelt (siehe #typify).
class RelationsController < ApplicationController
  before_action :load_source
  before_action :load_relation, only: [:show, :update]
  skip_before_action :verify_authenticity_token, only: [:typify]

  def show
    render json: relation_payload(@relation).merge(
      relation_types: RelationType.order(:name).pluck(:name)
    )
  end

  def update
    @relation.assign_attributes(permitted_attrs)
    @relation.recognized_by ||= current_actor
    @relation.recognized_at ||= Time.current
    if @relation.save
      render json: relation_payload(@relation)
    else
      render json: { errors: @relation.errors.full_messages }, status: :unprocessable_content
    end
  end

  # POST /knowledge_items/:source_uuid/relations/typify
  # Params: occurrence (1-basiert, Nth Wikilink im Body) — fuer untyped
  # Wikilinks im Body. ODER target_uuid + target_anchor — fuer Block-Anker-
  # Wikilinks aus dem Backlinks-Popover (#312 follow-up). Genau eine
  # Variante angeben. Erzeugt einen neuen anchor_id, schreibt ihn in
  # den Body, RelationSync legt die Relation an.
  def typify
    if params[:target_anchor].present?
      result = WikilinkTypify.call_for_target_anchor(
        actor: current_actor, knowledge_item: @source,
        target_uuid: params.require(:target_uuid).to_s,
        target_anchor: params[:target_anchor].to_s
      )
      err_msg = "Block-Anker-Wikilink (^#{params[:target_anchor]}) im Quell-Body nicht gefunden oder schon typisiert."
    else
      occurrence = params.require(:occurrence).to_i
      result = WikilinkTypify.call(actor: current_actor,
                                    knowledge_item: @source,
                                    occurrence: occurrence)
      err_msg = "Wikilink an Position #{occurrence} nicht typisierbar (existiert nicht, ist schon typed, oder Ziel unbekannt)."
    end

    if result
      render json: { anchor_id: result.anchor_id, target_uuid: result.target_uuid,
                     target_title: result.target_title }
    else
      render json: { error: err_msg }, status: :unprocessable_content
    end
  end

  private

  def load_source
    @source = KnowledgeItem.visible_to(current_actor).find_by!(uuid: params[:knowledge_item_uuid])
  end

  def load_relation
    @relation = Relation.find_by!(source_uuid: @source.uuid, anchor_id: params[:anchor_id])
  end

  def permitted_attrs
    params.require(:relation).permit(:label, :description, :direction, :recognized_role, :recognized_via)
  end

  def controller_resource_type
    "KnowledgeItem"
  end

  def controller_action_to_capability
    case action_name
    when "show"            then "read"
    when "update", "typify" then "update"
    else super
    end
  end

  def relation_payload(rel)
    {
      anchor_id:       rel.anchor_id,
      source_uuid:     rel.source_uuid,
      source_type:     rel.source_type,
      target_uuid:     rel.target_uuid,
      target_type:     rel.target_type,
      target_title:    target_title_for(rel),
      label:           rel.label,
      description:     rel.description,
      direction:       rel.direction,
      recognized_by:   rel.recognized_by&.name,
      recognized_role: rel.recognized_role,
      recognized_via:  rel.recognized_via,
      recognized_at:   rel.recognized_at,
      orphaned_at:     rel.orphaned_at
    }
  end

  def target_title_for(rel)
    return rel.target_uuid unless rel.target_type == "KnowledgeItem"
    KnowledgeItem.find_by(uuid: rel.target_uuid)&.title || rel.target_uuid
  end
end
