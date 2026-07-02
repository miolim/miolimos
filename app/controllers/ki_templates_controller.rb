class KiTemplatesController < ApplicationController
  # Picker-Suggest fuer den KI-Quick-Create-Slot (#301). JSON-Liste mit
  # { id, name, item_type, title, body }.
  def suggest
    q = params[:q].to_s.strip
    scope = KiTemplate.order(:name)
    scope = scope.search(q) if q.length >= 1
    @templates = scope.limit(8)

    render json: @templates.map { |t|
      {
        id:        t.id,
        name:      t.name,
        item_type: t.item_type,
        title:     t.title.to_s,
        body:      t.body.to_s
      }
    }
  end

  private

  def controller_resource_type
    "KnowledgeItem"
  end

  def controller_action_to_capability
    "create"
  end
end
