require "test_helper"

class TaskDependencyTest < ActiveSupport::TestCase
  setup do
    @creator = create_human
  end

  test "default dependency_type is finish_to_start" do
    a = create_task(creator: @creator)
    b = create_task(creator: @creator)
    dep = TaskDependency.create!(predecessor: a, successor: b)
    assert dep.finish_to_start?
  end

  test "rejects self-reference" do
    a = create_task(creator: @creator)
    dep = TaskDependency.new(predecessor: a, successor: a)
    refute_predicate dep, :valid?
  end

  test "rejects duplicate edge" do
    a = create_task(creator: @creator)
    b = create_task(creator: @creator)
    TaskDependency.create!(predecessor: a, successor: b)
    dup = TaskDependency.new(predecessor: a, successor: b)
    refute_predicate dup, :valid?
  end

  test "rejects direct cycle (a→b, b→a)" do
    a = create_task(creator: @creator)
    b = create_task(creator: @creator)
    TaskDependency.create!(predecessor: a, successor: b)

    bad = TaskDependency.new(predecessor: b, successor: a)
    refute_predicate bad, :valid?
    assert_includes bad.errors[:base].join(" "), "circular"
  end

  test "rejects indirect cycle (a→b→c, c→a)" do
    a = create_task(creator: @creator)
    b = create_task(creator: @creator)
    c = create_task(creator: @creator)

    TaskDependency.create!(predecessor: a, successor: b)
    TaskDependency.create!(predecessor: b, successor: c)

    bad = TaskDependency.new(predecessor: c, successor: a)
    refute_predicate bad, :valid?
  end

  test "allows diamond (a→b, a→c, b→d, c→d) — no cycle" do
    a = create_task(creator: @creator)
    b = create_task(creator: @creator)
    c = create_task(creator: @creator)
    d = create_task(creator: @creator)

    TaskDependency.create!(predecessor: a, successor: b)
    TaskDependency.create!(predecessor: a, successor: c)
    TaskDependency.create!(predecessor: b, successor: d)

    ok = TaskDependency.new(predecessor: c, successor: d)
    assert_predicate ok, :valid?
  end
end
