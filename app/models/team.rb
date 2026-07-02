class Team < ApplicationRecord
  has_many :team_memberships, dependent: :destroy
  has_many :actors, through: :team_memberships

  has_many :topics, dependent: :nullify
  has_many :capabilities, dependent: :destroy

  validates :name, presence: true, uniqueness: true
end
