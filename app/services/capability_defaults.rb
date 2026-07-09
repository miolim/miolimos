# #806: DIE eine Quelle für die Standard-Rechtematrix. Vorher lebte die
# Resource-Type-Liste doppelt (db/seeds.rb + lib/tasks/capabilities.rake)
# und driftete; jetzt hängen Seeds, capabilities:sync und das First-Run-
# Onboarding an derselben Definition.
#
# Rechtsmatrix:
#   HumanActors        → read/create/update/delete (Vollrechte)
#   Builder-Agents     → read/create/update/delete (commit/deploy-Workflow)
#   andere AgentActors → read/create/update (kein delete — opt-in pro Agent)
class CapabilityDefaults
  RESOURCE_TYPES = %w[Task Awaiting Contact Topic KnowledgeItem Communication
                      Actor OauthCredential Team Source InboxItem ActorView
                      ActivityEvent Document Invoice TimeEntry Event].freeze

  HUMAN_ACTIONS = %w[read create update delete].freeze
  AGENT_ACTIONS = %w[read create update].freeze

  # Vollrechte auf alle Resource-Types — für den Onboarding-Admin und
  # Seeds. Idempotent (find_or_initialize + überschreibende actions).
  def self.grant_full!(actor)
    grant!(actor, HUMAN_ACTIONS)
  end

  def self.grant_agent_default!(actor)
    grant!(actor, AGENT_ACTIONS)
  end

  def self.grant!(actor, actions)
    RESOURCE_TYPES.each do |rt|
      cap = Capability.find_or_initialize_by(actor: actor, resource_type: rt, effect: :allow)
      cap.actions = actions
      cap.save!
    end
  end
end
