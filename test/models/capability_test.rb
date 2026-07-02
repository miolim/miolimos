require "test_helper"

class CapabilityTest < ActiveSupport::TestCase
  test "actor XOR team: actor-only is valid" do
    cap = Capability.new(actor: create_human, resource_type: "Task", actions: %w[read])
    assert_predicate cap, :valid?
  end

  test "actor XOR team: team-only is valid" do
    cap = Capability.new(team: create_team, resource_type: "Task", actions: %w[read])
    assert_predicate cap, :valid?
  end

  test "actor XOR team: both set is invalid" do
    cap = Capability.new(actor: create_human, team: create_team, resource_type: "Task", actions: %w[read])
    refute_predicate cap, :valid?
    assert_includes cap.errors[:base].join(" "), "either actor OR team"
  end

  test "actor XOR team: neither set is invalid" do
    cap = Capability.new(resource_type: "Task", actions: %w[read])
    refute_predicate cap, :valid?
  end

  test "actions must be from VALID_ACTIONS" do
    cap = Capability.new(actor: create_human, resource_type: "Task", actions: %w[read bogus])
    refute_predicate cap, :valid?
    assert_includes cap.errors[:actions].join(" "), "bogus"
  end

  test "resource_type is required" do
    cap = Capability.new(actor: create_human, actions: %w[read])
    refute_predicate cap, :valid?
  end

  test "DB uniqueness on (actor, resource_type, effect)" do
    hans = create_human
    Capability.create!(actor: hans, resource_type: "Task", effect: :allow, actions: %w[read])
    assert_raises(ActiveRecord::RecordNotUnique) do
      Capability.create!(actor: hans, resource_type: "Task", effect: :allow, actions: %w[create])
    end
  end

  test "allow and deny on same resource coexist" do
    hans = create_human
    Capability.create!(actor: hans, resource_type: "Task", effect: :allow, actions: %w[read create update])
    Capability.create!(actor: hans, resource_type: "Task", effect: :deny,  actions: %w[delete])

    assert_equal 2, Capability.where(actor: hans, resource_type: "Task").count
  end

  test "DB check constraint rejects both actor and team" do
    assert_raises(ActiveRecord::StatementInvalid) do
      Capability.connection.execute(<<~SQL)
        INSERT INTO capabilities (actor_id, team_id, resource_type, actions, effect, scope, created_at, updated_at)
        VALUES (1, 1, 'Task', '[]'::jsonb, 0, '{}'::jsonb, now(), now())
      SQL
    end
  end
end
