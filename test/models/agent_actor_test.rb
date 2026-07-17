require "test_helper"

# #378 Phase 5 (Hans, 2026-05-26): Tests fuer AgentActor — Auto-Token,
# default Capabilities, regenerate.
class AgentActorTest < ActiveSupport::TestCase
  def build_agent(**attrs)
    AgentActor.new(name: "Bot", email: "bot-#{SecureRandom.hex(3)}@x.local",
                    description: "test", **attrs)
  end

  test "auto-generates api_token before validation" do
    agent = build_agent
    assert_nil agent.api_token
    agent.valid?
    assert agent.api_token.present?
    assert_equal 64, agent.api_token.length  # SecureRandom.hex(32) = 64 chars
  end

  test "preserves explicit api_token" do
    agent = build_agent(api_token: "explicit-token-1234")
    agent.valid?
    assert_equal "explicit-token-1234", agent.api_token
  end

  test "requires description" do
    agent = AgentActor.new(name: "B", email: "b@x.local")
    assert_not agent.valid?
    assert agent.errors[:description].any?
  end

  test "rejects duplicate api_token" do
    AgentActor.create!(name: "A", email: "a-#{SecureRandom.hex(3)}@x.local",
                        description: "x", api_token: "dup-token-foo")
    agent = build_agent(api_token: "dup-token-foo")
    assert_not agent.valid?
    # #1052: Eindeutigkeit läuft über den gespeicherten Digest.
    assert agent.errors[:api_token_digest].any?
  end

  # #1052: Klartext ist transient — DB hält nur den SHA256-Digest.
  test "api_token ist nach Reload nicht mehr lesbar, Digest bleibt" do
    agent = build_agent
    agent.save!
    token = agent.api_token
    assert token.present?
    assert_equal Actor.digest_api_token(token), agent.api_token_digest
    # reload behält Ivars derselben Instanz — entscheidend ist, dass eine
    # FRISCH geladene Instanz (= neuer Request) keinen Klartext mehr hat.
    fresh = AgentActor.find(agent.id)
    assert_nil fresh.api_token, "Klartext darf nicht persistiert sein"
    assert fresh.api_token_digest.present?
  end

  test "regenerate_api_token! creates a new token" do
    agent = AgentActor.create!(name: "R", email: "r-#{SecureRandom.hex(3)}@x.local",
                                description: "x")
    old = agent.api_token
    agent.regenerate_api_token!
    assert_not_equal old, agent.api_token
    assert_equal 64, agent.api_token.length
  end

  test "grant_default_capabilities! seeds read/create/update on all default types" do
    agent = AgentActor.create!(name: "G", email: "g-#{SecureRandom.hex(3)}@x.local",
                                description: "x")
    agent.grant_default_capabilities!
    AgentActor::DEFAULT_RESOURCE_TYPES.each do |type|
      cap = agent.capabilities.find_by(resource_type: type, effect: "allow")
      assert cap, "missing cap for #{type}"
      assert_equal %w[read create update], cap.actions
    end
  end

  test "grant_default_capabilities! with include_delete adds delete" do
    agent = AgentActor.create!(name: "GD", email: "gd-#{SecureRandom.hex(3)}@x.local",
                                description: "x")
    agent.grant_default_capabilities!(include_delete: true)
    cap = agent.capabilities.find_by(resource_type: "Task", effect: "allow")
    assert_includes cap.actions, "delete"
  end

  test "grant_default_capabilities! is idempotent" do
    agent = AgentActor.create!(name: "I", email: "i-#{SecureRandom.hex(3)}@x.local",
                                description: "x")
    agent.grant_default_capabilities!
    count = agent.capabilities.count
    agent.grant_default_capabilities!
    assert_equal count, agent.capabilities.count
  end
end
