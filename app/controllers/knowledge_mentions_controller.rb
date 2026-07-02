# Web-UI nested controller: /knowledge_items/:knowledge_item_uuid/mentions
# Picker-getriebenes Verlinken von Person/Org-KIs an ein KI.
class KnowledgeMentionsController < ApplicationController
  def create
    item = find_item
    ki   = resolve_mention_from_params

    if ki && ki.uuid != item.uuid
      KnowledgeItemMention.find_or_create_by!(knowledge_item: item, mentioned_uuid: ki.uuid)
    end

    respond_with_chips(item)
  end

  def destroy
    item = find_item
    ki   = KnowledgeItem.find_by(uuid: params[:id]) ||
           PersonKiResolver.find(params[:id])
    KnowledgeItemMention.find_by(knowledge_item: item, mentioned_uuid: ki&.uuid)&.destroy
    @unlinked_ki = ki

    respond_with_chips(item)
  end

  private

  def resolve_mention_from_params
    if (text = params[:create_with].to_s.strip).present?
      parts = text.split(/\s+/)
      first = parts.size > 1 ? parts[0..-2].join(" ") : nil
      last  = parts.last
      ki = FileProxy.create(
        actor:     Current.actor,
        title:     text,
        item_type: :person,
        content:   ""
      )
      ki.update!(first_name: first, last_name: last) if first || last
      ki
    else
      raw = params.require(:mentioned_uuid)
      KnowledgeItem.find_by(uuid: raw) || PersonKiResolver.find(raw)
    end
  end

  def find_item
    KnowledgeItem.find_by!(uuid: params[:knowledge_item_uuid])
  end

  def respond_with_chips(item)
    item.reload
    streams = [
      turbo_stream.replace("knowledge_contacts_chips_#{item.uuid}",
        partial: "knowledge_items/contacts_chips", locals: { item: item })
    ]
    if action_name == "destroy" && @unlinked_ki
      streams << helpers.toast_stream(
        message:  "Erwähnung '#{@unlinked_ki.display_name}' entfernt",
        undo_url: knowledge_item_mentions_path(knowledge_item_uuid: item.uuid),
        undo_payload: { mentioned_uuid: @unlinked_ki.uuid }
      )
    end
    respond_to do |format|
      format.turbo_stream { render turbo_stream: streams }
      format.json { render json: { ok: true } }
      format.html { redirect_back fallback_location: knowledge_item_path(item.uuid) }
    end
  end

  def controller_resource_type
    "KnowledgeItem"
  end

  def controller_action_to_capability
    "update"
  end
end
