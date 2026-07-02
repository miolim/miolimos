class SettingsController < ApplicationController
  include KnowledgeStackHelpers
  include Settings::BladeLoaders

  # #613: /settings ist eine Blade-Stack-Seite — Einstiegs-Blade ist die
  # Liste der Einstellungs-Bereiche (frühere Reiter-Leiste), ?stack=
  # kann Bereichs-Blades anhängen (settings:<page>).
  def index
    params[:stack] = "list:settings" if params[:stack].blank?
    @initial_stack_items  = build_initial_stack
    @initial_stack_bodies = bodies_for_initial_stack(@initial_stack_items)
    # Loader für alle Seiten-Blades im Stack — die View-Assigns werden
    # beim Render-Start kopiert, daher HIER (Ivars sind je Seite eindeutig).
    @initial_stack_items.each do |it|
      next unless it.kind == :settings_page
      loader = "load_#{it.id}"
      send(loader) if respond_to?(loader, true)
    end
  end

  private

  def controller_resource_type
    "Actor"  # wie Settings::BaseController — die Übersicht zeigt nur Einstiege
  end
end
