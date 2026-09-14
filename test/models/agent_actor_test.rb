require "test_helper"

# #378 Phase 5 (Hans, 2026-05-26): Tests fuer AgentActor — default
# Capabilities. #1499: Das Einzel-Token an der Actor-Spalte ist entfallen;
# Token-Regeln stehen in api_token_test, die Tuer in token_auth_test.
class AgentActorTest < ActiveSupport::TestCase
  test "requires description" do
    agent = AgentActor.new(name: "B", email: "b@x.local")
    assert_not agent.valid?
    assert agent.errors[:description].any?
  end

  test "ein neuer Agent hat kein Token von selbst" do
    agent = AgentActor.create!(name: "N", email: "n-#{SecureRandom.hex(3)}@x.local", description: "x")
    assert_empty agent.api_tokens
    refute_includes Actor.column_names, "api_token_digest", "die alte Token-Spalte ist entfallen"
  end

  test "Loeschen des Agenten nimmt seine Token mit" do
    agent = AgentActor.create!(name: "D", email: "d-#{SecureRandom.hex(3)}@x.local", description: "x")
    ApiToken.issue!(actor: agent, name: "Laptop")
    assert_difference "ApiToken.count", -1 do
      agent.destroy!
    end
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
