# Nested unter Awaiting: /awaitings/:awaiting_id/topics
class AwaitingTopicsController < ApplicationController
  include NestedTopicAssignment

  nested_topic_config parent_class: Awaiting,
                      join_class:   AwaitingTopic,
                      id_param:     :awaiting_id

  private

  def on_success(awaiting)
    awaiting.reload
    streams = [
      turbo_stream.replace("awaiting_topics_chips_#{awaiting.id}",
        partial: "awaitings/topics_chips", locals: { awaiting: awaiting })
    ]
    if action_name == "destroy" && @unlinked_topic
      streams << helpers.toast_stream(
        message:  "Thema '#{@unlinked_topic.name}' entfernt",
        undo_url: awaiting_topics_path(awaiting),
        undo_payload: { topic_id: @unlinked_topic.slug }
      )
    end
    respond_to do |format|
      format.turbo_stream { render turbo_stream: streams }
      format.html { redirect_back fallback_location: awaiting_path(awaiting) }
    end
  end
end
