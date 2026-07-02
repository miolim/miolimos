require "test_helper"

class TaskQueryTest < ActiveSupport::TestCase
  setup do
    @hans = create_human(email: "tq-#{SecureRandom.hex(3)}@t.local")
    @other = create_human(email: "other-#{SecureRandom.hex(3)}@t.local")

    @mine_open      = Task.create!(title: "mine open",    creator: @hans, assignee: @hans, status: :open)
    @mine_done      = Task.create!(title: "mine done",    creator: @hans, assignee: @hans, status: :done)
    @others_open    = Task.create!(title: "others open",  creator: @other, assignee: @other, status: :open)
    @unassigned     = Task.create!(title: "unassigned",   creator: @hans, assignee: nil, status: :open)
    @subtask        = Task.create!(title: "child",        creator: @hans, assignee: @hans, status: :open, parent: @mine_open)
  end

  def ids(rel) = rel.pluck(:id).sort

  test "default scope shows my open tasks + unassigned, hides subtasks and others" do
    q = TaskQuery.new({}, actor: @hans).relation
    assert_equal [@mine_open.id, @unassigned.id].sort, ids(q)
  end

  test "show_done=true includes done tasks" do
    q = TaskQuery.new({ show_done: "1" }, actor: @hans).relation
    assert_includes ids(q), @mine_done.id
    assert_includes ids(q), @mine_open.id
  end

  test "assignee_id=all drops the assignee filter (still no subtasks)" do
    q = TaskQuery.new({ assignee_id: "all" }, actor: @hans).relation
    assert_includes ids(q), @others_open.id
    refute_includes ids(q), @subtask.id
  end

  test "assignee_id=<other> filters to that actor" do
    q = TaskQuery.new({ assignee_id: @other.id.to_s }, actor: @hans).relation
    assert_equal [@others_open.id], ids(q)
  end

  # #665: tri-state Toggles im Haupt-Aufgaben-Blade.
  test "assignee_id=others zeigt nur fremd-zugewiesene (nicht meine, nicht unzugewiesen)" do
    q = TaskQuery.new({ assignee_id: "others" }, actor: @hans).relation
    assert_equal [@others_open.id], ids(q)
  end

  test "task_status=done zeigt nur Erledigte; =all beide; =open nur offene" do
    done = TaskQuery.new({ task_status: "done" }, actor: @hans).relation
    assert_equal [@mine_done.id], ids(done)

    all = TaskQuery.new({ task_status: "all" }, actor: @hans).relation
    assert_includes ids(all), @mine_open.id
    assert_includes ids(all), @mine_done.id

    open = TaskQuery.new({ task_status: "open" }, actor: @hans).relation
    assert_includes ids(open), @mine_open.id
    refute_includes ids(open), @mine_done.id
  end

  test "task_status hat Vorrang vor show_done" do
    q = TaskQuery.new({ task_status: "open", show_done: "1" }, actor: @hans).relation
    refute_includes ids(q), @mine_done.id
  end

  test "q=#<id> matches the task by primary key" do
    q = TaskQuery.new({ q: "##{@mine_open.id}" }, actor: @hans).relation
    assert_equal [@mine_open.id], ids(q)

    q2 = TaskQuery.new({ q: @mine_open.id.to_s }, actor: @hans).relation
    assert_equal [@mine_open.id], ids(q2)
  end

  test "q=<text> matches title substring case-insensitively" do
    Task.create!(title: "AURORA buy candles", creator: @hans, assignee: @hans, status: :open)
    Task.create!(title: "different",          creator: @hans, assignee: @hans, status: :open)

    rel = TaskQuery.new({ q: "aurora" }, actor: @hans).relation
    titles = rel.pluck(:title)
    assert_equal ["AURORA buy candles"], titles
  end

  test "tag filter selects only tasks with that tag" do
    bug   = Task.create!(title: "bug 1", tags: %w[bug],     creator: @hans, assignee: @hans, status: :open)
    feat  = Task.create!(title: "feat 1", tags: %w[feature], creator: @hans, assignee: @hans, status: :open)
    rel = TaskQuery.new({ tag: "bug" }, actor: @hans).relation
    ids = rel.pluck(:id)
    assert_includes ids,  bug.id
    refute_includes ids,  feat.id
  end

  test "priority filter accepts known values and ignores unknown" do
    high = Task.create!(title: "high", priority: :high, creator: @hans, assignee: @hans, status: :open)
    Task.create!(title: "normal",    priority: :normal, creator: @hans, assignee: @hans, status: :open)

    rel = TaskQuery.new({ priority: "high" }, actor: @hans).relation
    assert_equal [high.id], rel.pluck(:id) - [@mine_open.id, @unassigned.id] # high.id only

    # Bogus value → no priority filter applied (returns all open).
    rel2 = TaskQuery.new({ priority: "bogus" }, actor: @hans).relation
    assert_includes rel2.pluck(:id), high.id
    assert_includes rel2.pluck(:id), @mine_open.id
  end

  test "exposes filter values for view chips" do
    q = TaskQuery.new({ q: "  foo  ", tag: "bug", priority: "high",
                        assignee_id: "all", show_done: "1" }, actor: @hans)
    assert_equal "foo",  q.q
    assert_equal "bug",  q.tag
    assert_equal "high", q.priority
    assert_equal "all",  q.assignee_id
    assert_equal true,   q.show_done
  end

  test "blank-string filter values normalize to nil" do
    q = TaskQuery.new({ q: "   ", tag: "", priority: nil, assignee_id: "" }, actor: @hans)
    assert_nil q.q
    assert_nil q.tag
    assert_nil q.priority
    assert_nil q.assignee_id
  end

  test "commitment ordering: inbox, today, soon, later" do
    Task.delete_all
    later  = Task.create!(title: "L", creator: @hans, assignee: @hans, status: :open, commitment: :later)
    inbox  = Task.create!(title: "I", creator: @hans, assignee: @hans, status: :open, commitment: nil)
    soon   = Task.create!(title: "S", creator: @hans, assignee: @hans, status: :open, commitment: :soon)
    today  = Task.create!(title: "T", creator: @hans, assignee: @hans, status: :open, commitment: :today)

    # #409 (Hans, 2026-05-30) machte `created_at` zum Default-Sort; die
    # Commitment-Sektionen-Reihenfolge liegt seither auf dem Sort-Key
    # „manual" (else-Zweig mit COMMITMENT_ORDER). Diesen hier explizit
    # anfordern — sonst testet man den created_at-Default (Test war stale).
    q = TaskQuery.new({ sort: "manual" }, actor: @hans).relation
    assert_equal [inbox.id, today.id, soon.id, later.id], q.pluck(:id)
  end

  test "default sort ist created_at desc (jüngste oben, #409)" do
    Task.delete_all
    first  = Task.create!(title: "1", creator: @hans, assignee: @hans, status: :open)
    second = Task.create!(title: "2", creator: @hans, assignee: @hans, status: :open)

    q = TaskQuery.new({}, actor: @hans).relation
    assert_equal [second.id, first.id], q.pluck(:id)
  end
end
