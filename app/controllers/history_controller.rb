# #160 Phase 3: User-History. #631 (Hans, 2026-06-12): von der alten
# Split-Pane-Seite auf den Blade-Stack umgezogen — Einstieg ist das
# Verlauf-Listen-Blade (history/_list_blade_card), Klick öffnet die
# Entität als Blade im Stack. Die Daten lädt das Blade selbst
# (DISTINCT ON pro Entity, Typ-Filter client-seitig).
class HistoryController < ApplicationController
  include KnowledgeStackHelpers

  def index
    params[:stack] = "list:history" if params[:stack].blank?
    @initial_stack_items  = build_initial_stack
    @initial_stack_bodies = bodies_for_initial_stack(@initial_stack_items)
  end

  # #163 Phase 5a-3: Listen-Blade fuer Cross-Entity-Stack.
  def list_card
    render partial: "history/list_blade_card", layout: false
  end

  # #631 v2: nächste Verlaufs-Seite für den „Mehr laden"-Frame.
  def more
    render layout: false
  end

  private

  def controller_resource_type
    "Actor"
  end

  def controller_action_to_capability
    "read"
  end
end
