# #592: Bäume eines Topics anlegen (Linsen-Modell). Work-Tree- und
# Zweckgeflecht-Reiter sind Sichten auf dieselben TopicTrees — hier
# entsteht ein weiterer Baum (kind bestimmt nur Default-Name/Start-Linse).
class TopicTreesController < ApplicationController
  before_action :set_topic

  def create
    kind = TopicTree::KINDS.include?(params[:kind]) ? params[:kind] : "work"
    tree = @topic.topic_trees.create!(
      kind: kind,
      name: params[:name].presence,
      position: @topic.topic_trees.maximum(:position).to_i + 1
    )
    @tab = "trees"
    @current_tree_id = tree.id
    respond_to do |format|
      format.turbo_stream do
        # #596: nur die Gliederungs-Section ersetzen (Scroll-Erhalt).
        render turbo_stream: turbo_stream.replace_all(
          "[data-uuid^='list:topic:#{@topic.slug}'][data-current-tab='#{@tab}'] .topic-trees-section",
          partial: "topics/index_blade_work_tree_tab",
          locals: { topic: @topic }
        )
      end
      format.html { redirect_to topic_path(@topic, tab: @tab, tree_id: tree.id) }
    end
  end

  # #600 (Hans): Baum samt Knoten löschen — die KIs bleiben erhalten
  # (Knoten sind nur Struktur).
  def destroy
    tree = @topic.topic_trees.find(params[:id])
    tree.destroy!
    @tab = "trees"
    @current_tree_id = @topic.topic_trees.order(:position).first&.id
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace_all(
          "[data-uuid^='list:topic:#{@topic.slug}'][data-current-tab='trees'] .topic-trees-section",
          partial: "topics/index_blade_work_tree_tab",
          locals: { topic: @topic }
        )
      end
      format.html { redirect_to topic_path(@topic, tab: "trees") }
    end
  end

  private

  def set_topic
    @topic = Topic.visible_to(current_actor).find_by!(slug: params[:topic_slug])
  end

  def controller_resource_type     = "Topic"
  def controller_action_to_capability = "update"
end
