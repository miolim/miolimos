# Web-UI nested controller: /knowledge_items/:knowledge_item_id/topics
# Picker-getriebene Topic-Verbindung. Bei create_with wird das Topic
# inline angelegt und sofort verbunden.
class KnowledgeTopicsController < ApplicationController
  include NestedTopicAssignment

  nested_topic_config parent_class: KnowledgeItem,
                      join_class:   KnowledgeItemTopic,
                      id_param:     :knowledge_item_uuid,
                      with_position: false

  private

  def find_parent
    KnowledgeItem.find_by!(uuid: params[:knowledge_item_uuid])
  end

  def on_success(item)
    item.reload
    streams = [
      turbo_stream.replace("knowledge_topics_chips_#{item.uuid}",
        partial: "knowledge_items/topics_chips", locals: { item: item })
    ]
    # #484 (Hans, 2026-06-03): aus dem Topic-Reiter-Picker heraus die Row
    # des frisch zugewiesenen KIs sofort oben in die Liste prependen.
    if action_name == "create" && params[:tab_list].present?
      streams << turbo_stream.prepend(params[:tab_list],
        partial: "knowledge_items/list_row",
        locals: { item: item, topic_slug: params[:tab_topic].to_s, work_tree_count: 0 })
    end
    if action_name == "destroy" && @unlinked_topic
      streams << helpers.toast_stream(
        message:  "Thema '#{@unlinked_topic.name}' entfernt",
        undo_url: knowledge_item_topics_path(knowledge_item_uuid: item.uuid),
        undo_payload: { topic_id: @unlinked_topic.slug }
      )
    end
    respond_to do |format|
      format.turbo_stream { render turbo_stream: streams }
      format.json { render json: { ok: true } }
      format.html { redirect_back fallback_location: knowledge_item_path(item.uuid) }
    end
  end
end
