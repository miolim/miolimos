# Nested unter Communication: /communications/:communication_id/topics
class CommunicationTopicsController < ApplicationController
  include NestedTopicAssignment

  nested_topic_config parent_class: Communication,
                      join_class:   CommunicationTopic,
                      id_param:     :communication_id

  private

  def on_success(comm)
    comm.reload
    streams = [
      turbo_stream.replace("comm_topics_chips_#{comm.id}",
        partial: "communications/topics_chips", locals: { comm: comm }),
      turbo_stream.replace("communication_row_#{comm.id}",
        partial: "communications/row", locals: { comm: comm })
    ]
    if action_name == "destroy" && @unlinked_topic
      streams << helpers.toast_stream(
        message:  "Thema '#{@unlinked_topic.name}' entfernt",
        undo_url: communication_topics_path(comm),
        undo_payload: { topic_id: @unlinked_topic.slug }
      )
    end
    respond_to do |format|
      format.turbo_stream { render turbo_stream: streams }
      format.html { redirect_back fallback_location: communication_path(comm) }
    end
  end
end
