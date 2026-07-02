require "test_helper"

class TopicTest < ActiveSupport::TestCase
  test "requires name and unique slug" do
    creator = create_human
    Topic.create!(name: "A", slug: "alpha", creator: creator)
    dup = Topic.new(name: "B", slug: "alpha", creator: creator)
    refute_predicate dup, :valid?

    no_name = Topic.new(slug: "x-y", creator: creator)
    refute_predicate no_name, :valid?
  end

  test "slug format is enforced" do
    creator = create_human
    bad = Topic.new(name: "A", slug: "Bad Slug!", creator: creator)
    refute_predicate bad, :valid?
  end

  # #472 (Hans, 2026-06-02): research_question/research_kind entfernt —
  # zugehoeriger Test geloescht.

  test "status enum exposes active/paused/completed/archived" do
    creator = create_human
    active    = create_topic(creator: creator)
    paused    = Topic.create!(name: "p", slug: "p-#{SecureRandom.hex(2)}", creator: creator, status: :paused)
    completed = Topic.create!(name: "c", slug: "c-#{SecureRandom.hex(2)}", creator: creator, status: :completed)
    archived  = Topic.create!(name: "a", slug: "a-#{SecureRandom.hex(2)}", creator: creator, status: :archived)

    assert_includes Topic.active, active
    refute_includes Topic.active, paused
    refute_includes Topic.active, completed
    refute_includes Topic.active, archived
  end

  test "templates scope" do
    creator = create_human
    regular  = create_topic(creator: creator)
    template = create_topic(creator: creator, template: true)

    assert_includes     Topic.templates,     template
    refute_includes     Topic.templates,     regular
    assert_includes     Topic.non_templates, regular
    refute_includes     Topic.non_templates, template
  end

  test "ordered_tasks respects task_topics position" do
    creator = create_human
    topic   = create_topic(creator: creator)

    t1 = create_task(creator: creator, title: "first")
    t2 = create_task(creator: creator, title: "second")
    t3 = create_task(creator: creator, title: "third")

    TaskTopic.create!(task: t2, topic: topic, position: 2)
    TaskTopic.create!(task: t3, topic: topic, position: 3)
    TaskTopic.create!(task: t1, topic: topic, position: 1)

    assert_equal %w[first second third], topic.ordered_tasks.pluck(:title)
  end

  test "next_step_task returns the task flagged next_step=true" do
    creator = create_human
    topic   = create_topic(creator: creator)
    a = create_task(creator: creator, title: "a")
    b = create_task(creator: creator, title: "b")

    TaskTopic.create!(task: a, topic: topic, position: 1)
    TaskTopic.create!(task: b, topic: topic, position: 2, next_step: true)

    assert_equal b, topic.next_step_task
  end

  test "next_step_task is nil when no flag set" do
    creator = create_human
    topic   = create_topic(creator: creator)
    a = create_task(creator: creator, title: "a")
    TaskTopic.create!(task: a, topic: topic, position: 1)

    assert_nil topic.next_step_task
  end
end
