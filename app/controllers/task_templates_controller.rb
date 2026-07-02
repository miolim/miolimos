class TaskTemplatesController < ApplicationController
  # Picker-Suggest fuer das Quickadd-Formular. Liefert eine JSON-Liste
  # mit { id, title, description (gekuerzt), agent_actor_id, agent_name }
  # — Stimulus-Picker rendert das clientseitig.
  def suggest
    q        = params[:q].to_s.strip
    agent_id = params[:agent_id].presence

    scope = TaskTemplate.for_agent(agent_id)
    scope = scope.search(q) if q.length >= 1
    @templates = scope.limit(8)

    render json: @templates.map { |t|
      {
        id:             t.id,
        title:          t.title,
        description:    t.description.to_s,
        agent_actor_id: t.agent_actor_id,
        agent_name:     t.agent_actor&.name
      }
    }
  end

  private

  def controller_resource_type
    "Task"
  end

  def controller_action_to_capability
    "create"   # Picker-Nutzung erfordert Task-Create-Recht
  end
end
