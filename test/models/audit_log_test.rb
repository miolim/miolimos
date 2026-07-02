require "test_helper"

class AuditLogTest < ActiveSupport::TestCase
  test "requires actor, action, auditable" do
    log = AuditLog.new
    refute_predicate log, :valid?
  end

  test "records with polymorphic auditable" do
    actor = create_human
    topic = create_topic(creator: actor)

    log = AuditLog.create!(
      actor:     actor,
      action:    "created",
      auditable: topic,
      changes_data: { "name" => [nil, topic.name] },
      metadata:  { "source" => "test" }
    )

    reloaded = AuditLog.find(log.id)
    assert_equal topic, reloaded.auditable
    assert_equal "Topic", reloaded.auditable_type
    assert_equal({ "name" => [nil, topic.name] }, reloaded.changes_data)
  end

  test "stamps created_at automatically" do
    actor = create_human
    topic = create_topic(creator: actor)
    log = AuditLog.create!(actor: actor, action: "noop", auditable: topic)
    assert_not_nil log.created_at
    assert_in_delta Time.current, log.created_at, 10.seconds
  end

  test "is read-only after persistence" do
    actor = create_human
    topic = create_topic(creator: actor)
    log = AuditLog.create!(actor: actor, action: "noop", auditable: topic)

    assert_raises(ActiveRecord::ReadOnlyRecord) do
      log.update!(action: "changed")
    end
  end
end
