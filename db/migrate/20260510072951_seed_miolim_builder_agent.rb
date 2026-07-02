# Datenmigration: Legt den miolim_builder@miolim.de AgentActor an, der
# als Empfänger von Aufgaben fungiert, die Claude (im Claude-Code-CLI)
# autonom abarbeitet. Pro Projekt soll es einen eigenen Builder-Actor
# geben, damit man denselben Workflow auch in anderen Repos verwenden
# kann.
#
# Idempotent: bei jedem db:migrate-Lauf safe.
class SeedMiolimBuilderAgent < ActiveRecord::Migration[8.1]
  RESOURCE_TYPES = %w[Task Awaiting Contact Topic KnowledgeItem Communication
                      Actor OauthCredential Team Source].freeze
  FULL_ACTIONS   = %w[read create update delete].freeze

  def up
    actor = AgentActor.find_or_initialize_by(email: "miolim_builder@miolim.de")
    actor.assign_attributes(
      name:        "miolim Builder",
      description: "Autonomer Build-Agent für miolimOS — bekommt Aufgaben " \
                   "über die Tasks-Inbox zugewiesen und arbeitet sie ab.",
      active:      true
    )
    actor.save!

    RESOURCE_TYPES.each do |rt|
      cap = Capability.find_or_initialize_by(actor: actor, resource_type: rt, effect: "allow")
      next if cap.actions == FULL_ACTIONS
      cap.actions = FULL_ACTIONS
      cap.save!
    end
  end

  def down
    actor = AgentActor.find_by(email: "miolim_builder@miolim.de")
    return unless actor
    actor.capabilities.destroy_all
    actor.destroy
  end
end
