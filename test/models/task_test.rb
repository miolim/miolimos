require "test_helper"

class TaskTest < ActiveSupport::TestCase
  test "title is required" do
    creator = create_human
    t = Task.new(creator: creator)
    refute_predicate t, :valid?
  end

  test "status and priority enums" do
    creator = create_human
    t = create_task(creator: creator)
    assert t.open?
    t.done!
    assert t.done?

    t.priority = :urgent
    t.save!
    assert t.urgent?
  end

  test "toggle_done! switches status and stamps completed_at" do
    creator = create_human
    t = create_task(creator: creator)

    t.toggle_done!
    assert t.done?
    assert_not_nil t.completed_at

    t.toggle_done!
    assert t.open?
    assert_nil t.completed_at
  end

  test "open scope filters open tasks" do
    creator = create_human
    open_task = create_task(creator: creator)
    done_task = create_task(creator: creator, status: :done)

    assert_includes     Task.open, open_task
    refute_includes     Task.open, done_task
  end

  test "root_tasks scope filters parent_id nil" do
    creator = create_human
    root    = create_task(creator: creator)
    sub     = create_task(creator: creator, parent: root)

    assert_includes     Task.root_tasks, root
    refute_includes     Task.root_tasks, sub
    assert_equal [sub], root.subtasks
  end

  test "blocked? true when any predecessor is still open" do
    creator = create_human
    a = create_task(creator: creator)
    b = create_task(creator: creator)
    TaskDependency.create!(predecessor: a, successor: b)

    assert_predicate b, :blocked?
    refute_predicate a, :blocked?
  end

  test "blocked? false once predecessor is done" do
    creator = create_human
    a = create_task(creator: creator)
    b = create_task(creator: creator)
    TaskDependency.create!(predecessor: a, successor: b)

    a.done!
    refute_predicate b.reload, :blocked?
  end

  test "assignee defaults to Current.actor on create when not set explicitly" do
    creator = create_human
    Current.actor = creator
    t = Task.create!(title: "x", creator: creator)
    assert_equal creator, t.assignee
  ensure
    Current.actor = nil
  end

  test "explicit assignee on create wins over default" do
    creator  = create_human
    other    = create_human
    Current.actor = creator
    t = Task.create!(title: "x", creator: creator, assignee: other)
    assert_equal other, t.assignee
  ensure
    Current.actor = nil
  end

  test "skip_default_assignee leaves assignee nil even with Current.actor set" do
    creator = create_human
    Current.actor = creator
    t = Task.create!(title: "x", creator: creator, skip_default_assignee: true)
    assert_nil t.assignee
  ensure
    Current.actor = nil
  end

  test "assignee can be human or agent" do
    creator = create_human
    human   = create_human
    agent   = create_agent

    t1 = create_task(creator: creator, assignee: human)
    t2 = create_task(creator: creator, assignee: agent)

    assert_equal human, t1.assignee
    assert_equal agent, t2.assignee
  end

  # #743 (Hans): der grüne WIP-Rahmen der Checkbox sitzt im Card-Header. Wird
  # eine offene Card live aktualisiert, wenn ein Lauf die Aufgabe als WIP
  # markiert/freigibt? Der Header-Replace muss bei wip_actor_id-Wechsel feuern.
  test "wip_actor_id-Wechsel broadcastet den Card-Header (grüner Rahmen)" do
    creator = create_human
    agent   = AgentActor.create!(name: "Bauer", description: "x",
                                 email: "bauer-#{SecureRandom.hex(3)}@miolim.de")
    task    = create_task(creator: creator, status: :open)

    payloads = capture_all_broadcasts { task.update!(wip_actor_id: agent.id) }
    header   = payloads.find { |p| p.include?("task_header_#{task.id}") }
    assert header, "WIP-Setzen muss den Card-Header neu broadcasten"
    assert_includes header, "border-emerald-500"

    payloads = capture_all_broadcasts { task.update!(wip_actor_id: nil) }
    header   = payloads.find { |p| p.include?("task_header_#{task.id}") }
    assert header, "WIP-Freigeben muss den Card-Header neu broadcasten"
    assert_includes header, "border-slate-400"
  end

  # Fängt ALLE ActionCable-Broadcasts (Payloads als String) während des Blocks.
  def capture_all_broadcasts
    intercepted = []
    ActionCable.server.singleton_class.class_eval do
      alias_method :__orig_broadcast_t743, :broadcast
      define_method(:broadcast) do |channel, payload, **kw|
        intercepted << payload.to_s
        __orig_broadcast_t743(channel, payload, **kw)
      end
    end
    yield
    intercepted
  ensure
    ActionCable.server.singleton_class.class_eval do
      alias_method :broadcast, :__orig_broadcast_t743
      remove_method :__orig_broadcast_t743
    end
  end
end
