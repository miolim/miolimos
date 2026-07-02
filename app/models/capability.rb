class Capability < ApplicationRecord
  belongs_to :actor, optional: true
  belongs_to :team,  optional: true

  enum :effect, { allow: 0, deny: 1 }, default: :allow

  VALID_ACTIONS = %w[read create update delete].freeze

  validates :resource_type, presence: true
  validate  :actor_xor_team
  validate  :actions_are_valid

  private

  def actor_xor_team
    if actor_id.present? && team_id.present?
      errors.add(:base, "capability must belong to either actor OR team, not both")
    elsif actor_id.blank? && team_id.blank?
      errors.add(:base, "capability must belong to either actor or team")
    end
  end

  def actions_are_valid
    return unless actions.is_a?(Array)
    invalid = actions.map(&:to_s) - VALID_ACTIONS
    errors.add(:actions, "contains invalid entries: #{invalid.join(', ')}") if invalid.any?
  end
end
