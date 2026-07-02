class AccessGate
  class Unauthorized < StandardError; end

  ACTIONS = %w[read create update delete].freeze

  def self.authorize!(actor:, resource_type:, action:)
    unless can?(actor: actor, resource_type: resource_type, action: action)
      raise Unauthorized, "#{actor.name} is not allowed to #{action} #{resource_type}"
    end
  end

  def self.can?(actor:, resource_type:, action:)
    action = action.to_s

    actor_deny = Capability.where(actor_id: actor.id, resource_type: resource_type, effect: :deny)
    actor_deny.each do |cap|
      return false if cap.actions.include?(action)
    end

    actor_allow = Capability.where(actor_id: actor.id, resource_type: resource_type, effect: :allow)
    actor_allow.each do |cap|
      return true if cap.actions.include?(action)
    end

    team_ids = actor.team_memberships.pluck(:team_id)
    if team_ids.any?
      team_allow = Capability.where(team_id: team_ids, resource_type: resource_type, effect: :allow)
      team_allow.each do |cap|
        return true if cap.actions.include?(action)
      end
    end

    false
  end

  def self.accessible_actions(actor:, resource_type:)
    ACTIONS.select { |a| can?(actor: actor, resource_type: resource_type, action: a) }
  end
end
