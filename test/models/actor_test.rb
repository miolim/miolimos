require "test_helper"

class ActorTest < ActiveSupport::TestCase
  test "HumanActor requires email" do
    actor = HumanActor.new(name: "Test")
    refute_predicate actor, :valid?
    assert actor.errors.added?(:email, :blank)
  end

  test "HumanActor email must be unique" do
    HumanActor.create!(name: "A", email: "same@test.local")
    dup = HumanActor.new(name: "B", email: "same@test.local")
    refute_predicate dup, :valid?
    assert dup.errors.added?(:email, :taken, value: "same@test.local")
  end

  test "AgentActor auto-generates api_token on create" do
    agent = AgentActor.new(name: "Bot", description: "does stuff")
    assert_predicate agent, :valid?
    agent.save!
    assert_match(/\A[0-9a-f]{64}\z/, agent.api_token)
  end

  test "AgentActor api_token is unique" do
    a = AgentActor.create!(name: "Bot1", description: "x")
    b = AgentActor.new(name: "Bot2", description: "x", api_token: a.api_token)
    refute_predicate b, :valid?
  end

  test "AgentActor requires description" do
    agent = AgentActor.new(name: "Bot")
    refute_predicate agent, :valid?
    assert agent.errors.added?(:description, :blank)
  end

  test "STI type round-trips through Actor base" do
    human = HumanActor.create!(name: "H", email: "h-#{SecureRandom.hex(2)}@t.local")
    agent = AgentActor.create!(name: "A", description: "x")

    assert_kind_of HumanActor, Actor.find(human.id)
    assert_kind_of AgentActor, Actor.find(agent.id)
  end

  test "active scope filters on active flag" do
    on  = HumanActor.create!(name: "On",  email: "on-#{SecureRandom.hex(2)}@t.local", active: true)
    off = HumanActor.create!(name: "Off", email: "off-#{SecureRandom.hex(2)}@t.local", active: false)

    assert_includes     Actor.active, on
    refute_includes     Actor.active, off
  end

  test "regenerate_api_token! produces a new token" do
    agent = create_agent
    original = agent.api_token
    agent.regenerate_api_token!
    refute_equal original, agent.reload.api_token
  end
end
