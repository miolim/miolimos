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
      # #1677 (aus immoOS #1661): eine Stelle für alle — PersonKiResolver.aus_text!
      PersonKiResolver.aus_text!(text, item_type: params[:create_type].presence || :person,
                                       actor: Current.actor)
    else
      raw = params.require(:mentioned_uuid)
      # #1675: auch das ZIEL muss der Nutzer sehen dürfen.
      only_visible(KnowledgeItem.find_by(uuid: raw) || PersonKiResolver.find(raw))
    end
  end

  def find_item
    find_visible!(KnowledgeItem, params[:knowledge_item_uuid])   # #1675
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
