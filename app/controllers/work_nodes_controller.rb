# #325 (Hans, 2026-05-24): Work-Tree-CRUD-Endpoints (innerhalb des
# Topic-Scopes). Antwortet primaer mit Turbo-Streams, die den
# Work-Tree-Tab des Topic-Blades aktualisieren — analog zu den
# anderen Tab-Frame-Pfaden.
#
# Routes (siehe config/routes.rb):
#   POST   /topics/:slug/work_nodes
#   PATCH  /topics/:slug/work_nodes/:id
#   DELETE /topics/:slug/work_nodes/:id
class WorkNodesController < ApplicationController
  before_action :set_topic
  before_action :set_node, only: [:update, :destroy, :indent, :outdent]

  def create
    # #592: Knoten-Anlegen per Titel-Tippen (Zweckgeflecht). Trifft der
    # Titel eine BESTEHENDE KI (case-insensitive, keine Replies), wird
    # die verknüpft — sonst entsteht eine Stub-KI, getaggt mit
    # `zweckgeflecht` (Hans-Frage: Stubs erkennbar/filterbar halten).
    ki = if params[:knowledge_item_uuid].present?
           KnowledgeItem.find(params.require(:knowledge_item_uuid))
         else
           title = params.require(:title).to_s.strip
           # #592-Folge (Hans): keine Beschreibungs-Stubs — leere KI reicht.
           KnowledgeItem.by_title_ci(title).where.not(item_type: "reply").first ||
             FileProxy.create(actor: current_actor, title: title,
                              item_type: :note, tags: ["zweckgeflecht"], content: "")
         end
    parent = params[:parent_id].present? ? @topic.work_nodes.find(params[:parent_id]) : nil
    tree   = resolve_tree(parent)
    node = WorkNodeOps.create(
      topic: @topic, knowledge_item: ki, parent: parent,
      role: params.fetch(:role, "content"),
      position: params[:position]&.to_i,
      tree: tree
    )
    respond_with_work_tree(tab_for(node.tree), node.tree_id)
  rescue WorkNodeOps::Error => e
    render json: { error: e.message }, status: :unprocessable_content
  end

  def update
    if params[:role].present?
      WorkNodeOps.update_role(@node, params[:role])
    end
    # #592: Junktor (and|or) + IST-Markierung (chosen, exklusiv je
    # Verzweigung) — die Zweckgeflecht-Operationen.
    if params.key?(:junctor)
      WorkNodeOps.update_junctor(@node, params[:junctor])
    end
    if params.key?(:chosen)
      ActiveModel::Type::Boolean.new.cast(params[:chosen]) ? WorkNodeOps.choose(@node) : WorkNodeOps.unchoose(@node)
    end
    if params[:position].present?
      WorkNodeOps.reorder(@node, params[:position].to_i)
    end
    if params.key?(:parent_id)
      new_parent = params[:parent_id].present? ? @topic.work_nodes.find(params[:parent_id]) : nil
      WorkNodeOps.reparent(@node, new_parent, position: params[:position]&.to_i)
    end
    respond_with_work_tree(tab_for(@node.tree), @node.tree_id)
  rescue WorkNodeOps::Error => e
    render json: { error: e.message }, status: :unprocessable_content
  end

  def destroy
    tab = tab_for(@node.tree)
    tree_id = @node.tree_id
    WorkNodeOps.remove(@node)
    respond_with_work_tree(tab, tree_id)
  end

  # #325 (Hans, 2026-05-24): Indent/Outdent fuer Outline-Editor-
  # Ergonomie (Tab / Shift-Tab Alternative).
  def indent
    WorkNodeOps.indent(@node)
    respond_with_work_tree(tab_for(@node.tree), @node.tree_id)
  rescue WorkNodeOps::Error => e
    render json: { error: e.message }, status: :unprocessable_content
  end

  def outdent
    WorkNodeOps.outdent(@node)
    respond_with_work_tree(tab_for(@node.tree), @node.tree_id)
  rescue WorkNodeOps::Error => e
    render json: { error: e.message }, status: :unprocessable_content
  end

  private

  def set_topic
    @topic = Topic.visible_to(current_actor).find_by!(slug: params[:topic_slug])
    @tab   = "trees"
  end

  def set_node
    @node = @topic.work_nodes.find(params[:id])
  end

  # #592: Baum bestimmen — explizit (tree_id/tree_kind=purpose, lazy
  # angelegt) oder implizit über den Parent; sonst Default-Work-Tree
  # (in WorkNodeOps).
  def resolve_tree(parent)
    return @topic.topic_trees.find(params[:tree_id]) if params[:tree_id].present?
    if params[:tree_kind] == "purpose"
      return @topic.topic_trees.purpose.first ||
             @topic.topic_trees.create!(kind: "purpose", name: "Mittel-Zweck-Baum", position: 2)
    end
    parent&.tree
  end

  # #592-Konsolidierung: ein Gliederungen-Reiter für alle Bäume.
  def tab_for(_tree) = "trees"

  def respond_with_work_tree(tab = "work_tree", tree_id = nil)
    @tab = tab
    # #592 Linsen: Re-Render bleibt auf dem gerade bearbeiteten Baum.
    @current_tree_id = tree_id
    respond_to do |format|
      format.turbo_stream do
        # #325 Phase 2.1 v2: nur Topic-Blades mit work_tree-Tab werden
        # serverseitig neu gerendert (replace_all per CSS-Selector
        # auf `[data-current-tab="work_tree"]`). Andere Topic-Blades
        # (z.B. Wissen-Tab in der zweiten Instanz) bleiben unangetastet
        # — wir wollen den Tab nicht ungewollt umschalten.
        # #356 (Hans, 2026-05-25): Seit #350 trägt der work-tree-Tab im
        # Stack die UUID `list:topic:<slug>:work_tree` (mit Tab-Suffix).
        # Der alte exact-match-Selektor `data-uuid='list:topic:<slug>'`
        # matched damit nicht mehr → UI aktualisiert sich nicht, der
        # User klickt nochmal und triggert dann legitim die „Indent
        # unmoeglich/Outdent unmoeglich"-Fehlermeldung. Fix: prefix-
        # Match mit `^=`. Die data-current-tab-Bedingung haelt das
        # eng genug (nur work_tree-Blades).
        # #596: NUR die Gliederungs-Section ersetzen, nicht das ganze
        # Blade — sonst springt die Scrollposition nach jeder Knoten-
        # Änderung (heading/content, Junktor, IST, …) an den Anfang.
        render turbo_stream: turbo_stream.replace_all(
          "[data-uuid^='list:topic:#{@topic.slug}'][data-current-tab='#{@tab}'] .topic-trees-section",
          partial: "topics/index_blade_work_tree_tab",
          locals: { topic: @topic }
        )
      end
      format.html { redirect_to topic_path(@topic, tab: @tab) }
    end
  end

  def controller_resource_type     = "Topic"
  def controller_action_to_capability
    case action_name
    when "create", "update", "destroy" then "update"
    else super
    end
  end
end
