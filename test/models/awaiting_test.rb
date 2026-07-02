require "test_helper"

class AwaitingTest < ActiveSupport::TestCase
  setup do
    @hans = create_human
  end

  test "requires title and follow_up_at" do
    a = Awaiting.new(creator: @hans)
    refute_predicate a, :valid?
    assert_includes a.errors[:title], a.errors.generate_message(:title, :blank)
    assert_includes a.errors[:follow_up_at], a.errors.generate_message(:follow_up_at, :blank)
  end

  test "overdue? is true when open and follow_up_at in the past" do
    a = Awaiting.create!(creator: @hans, title: "x", follow_up_at: Date.today - 1)
    assert_predicate a, :overdue?

    b = Awaiting.create!(creator: @hans, title: "x", follow_up_at: Date.today + 1)
    refute_predicate b, :overdue?

    c = Awaiting.create!(creator: @hans, title: "x", follow_up_at: Date.today - 1, status: :resolved)
    refute_predicate c, :overdue?
  end

  test "overdue, due_soon scopes" do
    overdue = Awaiting.create!(creator: @hans, title: "o", follow_up_at: Date.today - 2)
    soon    = Awaiting.create!(creator: @hans, title: "s", follow_up_at: Date.today + 1)
    far     = Awaiting.create!(creator: @hans, title: "f", follow_up_at: Date.today + 10)

    assert_includes Awaiting.overdue, overdue
    refute_includes Awaiting.overdue, soon
    assert_includes Awaiting.due_soon, soon
    refute_includes Awaiting.due_soon, far
  end

  test "resolve! stamps resolved_at and sets note" do
    a = Awaiting.create!(creator: @hans, title: "x", follow_up_at: Date.today + 3)
    a.resolve!(note: "Got the answer")
    assert a.reload.resolved?
    assert_not_nil a.resolved_at
    assert_equal "Got the answer", a.resolution_note
  end

  test "days_waiting counts from created_at" do
    a = Awaiting.create!(creator: @hans, title: "x", follow_up_at: Date.today + 3)
    # Uhrzeit festlegen, damit to_date nicht über Mitternacht rutscht
    a.update_column(:created_at, (Date.today - 5).noon)
    assert_equal 5, a.days_waiting
  end

  test "topics association via awaiting_topics" do
    topic = create_topic(creator: @hans)
    a = Awaiting.create!(creator: @hans, title: "x", follow_up_at: Date.today + 3)
    AwaitingTopic.create!(awaiting: a, topic: topic)
    assert_includes a.topics, topic
  end
end
