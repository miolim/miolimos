module Gated
  extend ActiveSupport::Concern

  included do
    before_action :enforce_access_gate
  end

  private

  def enforce_access_gate
    AccessGate.authorize!(
      actor: current_actor,
      resource_type: controller_resource_type,
      action: controller_action_to_capability
    )
  end

  def controller_action_to_capability
    case action_name
    when "index", "show" then "read"
    when "new", "create" then "create"
    when "edit", "update" then "update"
    when "destroy"       then "delete"
    else
      # #564: fail-closed statt fail-open. Vorher lief JEDE unbekannte
      # Custom-Action mit "read" — 35 mutierende Actions (publish, stop,
      # link, …) waren so mit Lese-Capability erreichbar. Jetzt entscheidet
      # das HTTP-Verb: GET/HEAD lesen, alles andere braucht mindestens
      # update. Bewusste Ausnahmen (POST mit Lese-Semantik wie resolve/
      # mark_read/toggle_pin) deklarieren Controller explizit per Override.
      request.get? || request.head? ? "read" : "update"
    end
  end

  def controller_resource_type
    controller_name.classify
  end
end
