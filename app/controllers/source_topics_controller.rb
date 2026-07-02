# #494 (Hans, 2026-06-03): Web-Pendant zu Api::V1::SourceTopicsController.
# Quelle↔Thema verknuepfen + Relevanz/Notiz pflegen — bisher gab es das
# nur ueber die API, das Web zeigte die Relevanz read-only. Antwort als
# turbo_stream, das die Recherche-Quellen-Sektion des Topics neu rendert.
#
#   POST   /sources/:source_slug/topics       — zuweisen ({topic_id, relevance?})
#   PATCH  /sources/:source_slug/topics/:id    — Relevanz/Notiz (:id = topic_id)
#   DELETE /sources/:source_slug/topics/:id    — Zuordnung entfernen
class SourceTopicsController < ApplicationController
  before_action :load_source

  def create
    topic = Topic.find(params.require(:topic_id))
    st = SourceTopic.find_or_initialize_by(source: @source, topic: topic)
    st.relevance = params[:relevance].presence || st.relevance || "relevant"
    st.reached = ActiveModel::Type::Boolean.new.cast(params[:reached]) if params.key?(:reached)
    st.note = params[:note] if params.key?(:note)
    st.save!
    respond_with_section(topic)
  end

  def update
    topic = Topic.find(params[:id])
    st = @source.source_topics.find_by!(topic_id: topic.id)
    st.relevance = params[:relevance] if params[:relevance].present?
    # #575: zweite Dimension erreicht/nicht-erreicht, unabhängig vom Urteil.
    st.reached = ActiveModel::Type::Boolean.new.cast(params[:reached]) if params.key?(:reached)
    st.note = params[:note] if params.key?(:note)
    st.save!
    respond_with_section(topic)
  end

  def destroy
    topic = Topic.find(params[:id])
    @source.source_topics.find_by(topic_id: topic.id)&.destroy
    respond_with_section(topic)
  end

  private

  def load_source
    @source = Source.find_by!(slug: params[:source_slug])
  end

  def respond_with_section(topic)
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace(
          "topic_research_sources_#{topic.id}",
          partial: "topics/research_sources", locals: { topic: topic })
      end
      format.html { redirect_back fallback_location: topic_path(topic) }
    end
  end

  def controller_resource_type
    "Source"
  end

  def controller_action_to_capability
    case action_name
    when "create"  then "create"
    when "destroy" then "delete"
    else                "update"
    end
  end
end
