# #592 Z2: Fokusansicht auf einen Baum-Knoten — der lokale Ausschnitt um
# den Fokus (Pfadleisten, Warum?/Wie?, Kontext- und Verfeinerungs-Kasten)
# nach der Spezifikation [[prompt_fokusansicht_zweckgeflecht]] / PoC.
# Blade-Identität = Einstiegs-Knoten (:id); die Navigation läuft als
# Turbo-Frame in der Card (?focus=<node>), analog Kalender-Monatswechsel.
class TreeFocusController < ApplicationController
  def card
    @entry = WorkNode.visible_to(current_actor).includes(:tree, :topic).find(params[:id])
    @focus = params[:focus].present? ? @entry.tree.nodes.find(params[:focus]) : @entry
    render partial: "tree_focus/blade", locals: { entry: @entry, focus: @focus }, layout: false
  end

  private

  def controller_resource_type        = "Topic"
  def controller_action_to_capability = "read"
end
