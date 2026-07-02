class TeamMembership < ApplicationRecord
  belongs_to :team
  belongs_to :actor

  enum :role, { owner: 0, member: 1 }, default: :member

  validates :actor_id, uniqueness: { scope: :team_id }
end
