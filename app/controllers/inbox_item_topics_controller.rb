# #171: Nested unter InboxItem — /inbox/:inbox_item_id/topics. Identische
# Mechanik wie TaskTopicsController & co.
class InboxItemTopicsController < ApplicationController
  include NestedTopicAssignment

  nested_topic_config parent_class: InboxItem,
                      join_class:   InboxItemTopic,
                      id_param:     :inbox_item_id

  private

  def on_success(item)
    item.reload
    streams = [
      turbo_stream.replace("inbox_item_topics_chips_#{item.id}",
        partial: "inbox_items/topics_chips", locals: { item: item })
    ]
    if action_name == "destroy" && @unlinked_topic
      streams << helpers.toast_stream(
        message:  "Thema '#{@unlinked_topic.name}' entfernt",
        undo_url: inbox_item_topics_path(item),
        undo_payload: { topic_id: @unlinked_topic.slug }
      )
    end
    respond_to do |format|
      format.turbo_stream { render turbo_stream: streams }
      format.html { redirect_back fallback_location: inbox_item_path(item) }
    end
  end
end
