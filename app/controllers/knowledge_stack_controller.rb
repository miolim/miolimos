# #203 Phase E.1: Sliding-Pane-Stack-spezifische Actions, ausgelagert
# aus KnowledgeItemsController:
#
#   GET  /pinned                                  → #pinned   (#191)
#   POST /knowledge_items/:uuid/toggle_pin        → #toggle_pin (#191)
#   GET  /knowledge_items/:uuid/card              → #card    (Stack-Fragment)
#   GET  /knowledge_items/:uuid/detail_pane       → #detail_pane (#196)
#
# Alle vier sind "read"-Kapazitaet auf KnowledgeItem; CSRF wird fuer
# toggle_pin geskippt (Stimulus-fetch ohne Form). Routes bleiben
# unveraendert (siehe config/routes.rb), nur die Klasse ist neu.
class KnowledgeStackController < ApplicationController
  include KnowledgeStackHelpers

  before_action :set_item, only: [:card, :detail_pane, :toggle_pin, :refs_card]

  skip_before_action :verify_authenticity_token, only: [:toggle_pin]

  # #191/#229: Persoenliche Pin-Liste als Blade-Stack-Page. Initial-
  # Stack = `list:pinned` (eine Listen-Blade mit den Pins), `?stack=`-
  # Param kann zusaetzliche Detail-Blades anhaengen. Damit reiht sich
  # /pinned in die selbe Architektur wie /tasks, /dashboard, /topics/:slug
  # ein — keine eigene Aside-Layout mehr.
  def pinned
    if params[:stack].blank?
      params[:stack] = "list:pinned"
    end
    @initial_stack_items  = build_initial_stack
    @initial_stack_bodies = bodies_for_initial_stack(@initial_stack_items)
  end

  # #191: 📌-Toggle aus der KI-Toolbar. JSON-Response fuer den Stimulus-
  # Controller, damit der das Icon und ggf. den Sidebar-Counter live
  # aktualisieren kann.
  def toggle_pin
    pin = KnowledgeItemPin.find_by(actor_id: current_actor.id,
                                   knowledge_item_id: @item.uuid)
    if pin
      pin.destroy!
      pinned = false
    else
      KnowledgeItemPin.create!(actor: current_actor, knowledge_item: @item)
      pinned = true
    end
    count = KnowledgeItemPin.for_actor(current_actor).count
    render json: { pinned: pinned, count: count, uuid: @item.uuid }
  end

  # #163 Phase 5a-3: Listen-Blade „Gepinnt" fuer Cross-Entity-Stack.
  def pinned_list_card
    render partial: "knowledge_items/pinned_list_blade_card", layout: false
  end

  # Card-Fragment fuer den Sliding-Pane-Stack. Liefert nur das Detail-
  # Partial, kein Layout — wird vom blade-stack-Controller via fetch
  # geholt und ins DOM appended.
  def card
    @body_html = load_body_html(@item)
    render partial: "knowledge_items/stack_card",
      locals: { item: @item, body_html: @body_html },
      layout: false
  end

  # #343 (Hans, 2026-05-25): Reference-Blade — listet alle Wikilink-
  # Ziele dieser KI in Source-Reihenfolge als eigene Stack-Card.
  def refs_card
    render partial: "knowledge_items/refs_blade",
      locals: { item: @item },
      layout: false
  end

  # #196: Detail-Pane fuer die History-Page. Rendert das KI-Detail in
  # einer statischen `knowledge_detail`-Frame-Huelle.
  # #231: ohne Turbo-Frame-Request (= Mobile-Klick aus History-Liste,
  # wo viewport-frame-Controller das data-turbo-frame entfernt) leitet
  # die Action auf die Stack-Page um — sonst sieht der User die
  # layoutlose Frame-Antwort (Icons riesig, kein CSS). Erste Blade ist
  # die Verlaufs-Liste, damit der User in den Kontext zurueck kann
  # (Hans-Bericht #231 follow-up: „erste Blade sollte der Verlauf sein").
  def detail_pane
    if !turbo_frame_request?
      redirect_to knowledge_items_path(stack: "list:history,#{@item.uuid}") and return
    end
    @body_html = load_body_html(@item)
    render partial: "knowledge_items/detail_pane",
      locals: { item: @item, body_html: @body_html },
      layout: false
  end

  private

  def set_item
    # #602 S1: unsichtbare KIs verhalten sich wie nicht existent (404).
    @item = KnowledgeItem.visible_to(current_actor).find(params[:uuid])
  end

  def controller_resource_type
    "KnowledgeItem"
  end

  def controller_action_to_capability
    "read"
  end
end
