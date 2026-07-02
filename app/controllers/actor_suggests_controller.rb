# #384 Phase 2 (Hans, 2026-05-27): Actor-Suggest fuer @-Mention-
# Autocomplete im KI-Editor. Returnt JSON-Liste der App-Nutzer
# (Human + Agent), die als @-Mention-Adressat infrage kommen.
class ActorSuggestsController < ApplicationController
  def index
    q = params[:q].to_s.strip.downcase
    scope = Actor.active.order(:name)
    if q.present?
      like = "%#{q}%"
      scope = scope.where("LOWER(name) LIKE :q OR LOWER(email) LIKE :q", q: like)
    end
    actors = scope.limit(10)
    render json: actors.map { |a|
      slug = a.name.to_s.parameterize.presence || "actor-#{a.id}"
      {
        id:    a.id,
        slug:  slug,
        name:  a.name,
        email: a.email,
        kind:  a.type.to_s.sub(/Actor\z/, "").downcase   # "human" / "agent"
      }
    }
  end

  private

  def controller_resource_type        = "Actor"
  def controller_action_to_capability = "read"
end
