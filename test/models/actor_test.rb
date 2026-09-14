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

  # #1058-Nachfund (2026-07-18): `@immoos-builder` (Bindestrich) fand den
  # Actor `immoos_builder` (Unterstrich) nicht — Mention rendert als
  # Missing-Pill, keine actor_mentions-Row. `-`/`_`/Leerzeichen sind beim
  # Lookup aequivalent.
  test "find_by_mention_slug treats hyphen, underscore and space as equivalent" do
    spaced     = HumanActor.create!(name: "Miolim Builder", email: "mb-#{SecureRandom.hex(2)}@t.local")
    underscore = AgentActor.create!(name: "immoos_builder", description: "x")

    assert_equal spaced,     Actor.find_by_mention_slug("miolim-builder")
    assert_equal underscore, Actor.find_by_mention_slug("immoos-builder")
    assert_equal underscore, Actor.find_by_mention_slug("immoos_builder")
  end

  test "find_by_mention_slug falls back to the email local part" do
    actor = HumanActor.create!(name: "Völlig Anders", email: "immoos_chef@t.local")

    assert_equal actor, Actor.find_by_mention_slug("immoos-chef")
    assert_nil Actor.find_by_mention_slug("gibt-es-nicht")
  end
end
