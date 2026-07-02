require "test_helper"

class TeamTest < ActiveSupport::TestCase
  test "team name is required and unique" do
    Team.create!(name: "alpha")
    dup = Team.new(name: "alpha")
    refute_predicate dup, :valid?
  end

  test "membership role defaults to member and supports owner" do
    team = create_team
    actor = create_human
    m = TeamMembership.create!(team: team, actor: actor)
    assert m.member?

    other = create_human
    o = TeamMembership.create!(team: team, actor: other, role: :owner)
    assert o.owner?
  end

  test "actor cannot join same team twice" do
    team = create_team
    actor = create_human
    TeamMembership.create!(team: team, actor: actor)
    dup = TeamMembership.new(team: team, actor: actor)
    refute_predicate dup, :valid?
  end

  test "team has_many actors via memberships" do
    team = create_team
    a = create_human
    b = create_agent
    TeamMembership.create!(team: team, actor: a, role: :owner)
    TeamMembership.create!(team: team, actor: b, role: :member)

    assert_equal [a, b].to_set, team.actors.to_set
  end
end
