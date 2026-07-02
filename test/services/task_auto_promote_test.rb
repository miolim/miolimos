require "test_helper"

class TaskAutoPromoteTest < ActiveSupport::TestCase
  setup do
    @hans = create_human
  end

  test "promotes tasks with due_date <= today+1 to today" do
    t1 = Task.create!(title: "due heute", creator: @hans, assignee: @hans,
                      due_date: Date.current)
    t2 = Task.create!(title: "due morgen", creator: @hans, assignee: @hans,
                      due_date: Date.current + 1)

    TaskAutoPromote.run!(@hans)

    assert_equal "today", t1.reload.commitment
    assert_equal "today", t2.reload.commitment
  end

  test "promotes tasks with due_date in [today+2..today+7] to soon" do
    t = Task.create!(title: "in 5 tagen", creator: @hans, assignee: @hans,
                     due_date: Date.current + 5)

    TaskAutoPromote.run!(@hans)

    assert_equal "soon", t.reload.commitment
  end

  test "leaves far-future tasks in inbox (commitment nil)" do
    t = Task.create!(title: "weit weg", creator: @hans, assignee: @hans,
                     due_date: Date.current + 30)

    TaskAutoPromote.run!(@hans)

    assert_nil t.reload.commitment
  end

  test "leaves tasks without due_date untouched" do
    t = Task.create!(title: "ohne datum", creator: @hans, assignee: @hans)

    TaskAutoPromote.run!(@hans)

    assert_nil t.reload.commitment
  end

  test "does not overwrite manual commitment (user wins)" do
    t = Task.create!(title: "manuell später", creator: @hans, assignee: @hans,
                     due_date: Date.current, commitment: :later)

    TaskAutoPromote.run!(@hans)

    assert_equal "later", t.reload.commitment
  end

  test "ignores tasks of other actors" do
    other = create_human(email: "other-#{SecureRandom.hex(2)}@t.local")
    t = Task.create!(title: "fremd", creator: other, assignee: other,
                     due_date: Date.current)

    TaskAutoPromote.run!(@hans)

    assert_nil t.reload.commitment
  end

  test "ignores done tasks" do
    t = Task.create!(title: "fertig", creator: @hans, assignee: @hans,
                     due_date: Date.current, status: :done, completed_at: Time.current)

    TaskAutoPromote.run!(@hans)

    assert_nil t.reload.commitment
  end

  test "is idempotent" do
    t = Task.create!(title: "due heute", creator: @hans, assignee: @hans,
                     due_date: Date.current)
    TaskAutoPromote.run!(@hans)
    TaskAutoPromote.run!(@hans)
    assert_equal "today", t.reload.commitment
  end
end
