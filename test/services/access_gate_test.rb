require "test_helper"

class AccessGateTest < ActiveSupport::TestCase
  setup do
    @actor = create_human
  end

  test "default deny when no capabilities exist" do
    refute AccessGate.can?(actor: @actor, resource_type: "Task", action: "read")
  end

  test "actor-level allow grants access" do
    grant(@actor, "Task", %w[read create])
    assert AccessGate.can?(actor: @actor, resource_type: "Task", action: "read")
    assert AccessGate.can?(actor: @actor, resource_type: "Task", action: "create")
    refute AccessGate.can?(actor: @actor, resource_type: "Task", action: "delete")
  end

  test "actor-level deny beats actor-level allow" do
    grant(@actor, "Task", %w[read create update delete])
    grant(@actor, "Task", %w[delete], effect: :deny)
    refute AccessGate.can?(actor: @actor, resource_type: "Task", action: "delete")
    assert AccessGate.can?(actor: @actor, resource_type: "Task", action: "update")
  end

  test "team allow grants access to member" do
    team = create_team
    TeamMembership.create!(team: team, actor: @actor)
    grant(team, "Topic", %w[read])

    assert AccessGate.can?(actor: @actor, resource_type: "Topic", action: "read")
  end

  test "actor-level deny beats team allow (most important rule)" do
    team = create_team
    TeamMembership.create!(team: team, actor: @actor)
    grant(team, "Topic", %w[read create])
    grant(@actor, "Topic", %w[read], effect: :deny)

    refute AccessGate.can?(actor: @actor, resource_type: "Topic", action: "read")
    assert AccessGate.can?(actor: @actor, resource_type: "Topic", action: "create")
  end

  test "non-member does not inherit team allow" do
    team = create_team
    grant(team, "Topic", %w[read])
    refute AccessGate.can?(actor: @actor, resource_type: "Topic", action: "read")
  end

  test "allow for other resource_type does not leak" do
    grant(@actor, "Task", %w[read])
    refute AccessGate.can?(actor: @actor, resource_type: "Topic", action: "read")
  end

  test "accessible_actions returns effective action set" do
    grant(@actor, "Task", %w[read create update delete])
    grant(@actor, "Task", %w[delete], effect: :deny)

    assert_equal %w[read create update].sort,
                 AccessGate.accessible_actions(actor: @actor, resource_type: "Task").sort
  end

  test "authorize! raises Unauthorized on deny" do
    assert_raises(AccessGate::Unauthorized) do
      AccessGate.authorize!(actor: @actor, resource_type: "Task", action: "read")
    end
  end

  test "authorize! is silent on allow" do
    grant(@actor, "Task", %w[read])
    assert_nothing_raised do
      AccessGate.authorize!(actor: @actor, resource_type: "Task", action: "read")
    end
  end

  test "string and symbol actions are equivalent" do
    grant(@actor, "Task", %w[read])
    assert AccessGate.can?(actor: @actor, resource_type: "Task", action: :read)
    assert AccessGate.can?(actor: @actor, resource_type: "Task", action: "read")
  end

  test "multiple teams union their allow sets" do
    team_a = create_team
    team_b = create_team
    TeamMembership.create!(team: team_a, actor: @actor)
    TeamMembership.create!(team: team_b, actor: @actor)
    grant(team_a, "Task",    %w[read])
    grant(team_b, "Contact", %w[create])

    assert AccessGate.can?(actor: @actor, resource_type: "Task",    action: "read")
    assert AccessGate.can?(actor: @actor, resource_type: "Contact", action: "create")
  end
end
