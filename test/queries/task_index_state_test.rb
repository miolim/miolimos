require "test_helper"

class TaskIndexStateTest < ActiveSupport::TestCase
  setup do
    @hans = create_human
    grant(@hans, "Task", %w[read create update])
  end

  test "Default-Group ist :time" do
    state = TaskIndexState.new(params: ActionController::Parameters.new({}), actor: @hans)
    assert_equal :time, state.group_by
    assert state.sections.is_a?(Array)
    assert_nil state.topic_sections
  end

  test "group=topic schaltet auf Topic-Mode" do
    state = TaskIndexState.new(
      params: ActionController::Parameters.new(group: "topic"), actor: @hans
    )
    assert_equal :topic, state.group_by
    assert state.topic_sections.is_a?(Array)
    assert_nil state.sections
  end

  test "by=topic ist Backward-Compat zu group=topic" do
    state = TaskIndexState.new(
      params: ActionController::Parameters.new(by: "topic"), actor: @hans
    )
    assert_equal :topic, state.group_by
  end

  test "Time-Sections enthalten alle vier Wann-Stufen in fester Reihenfolge" do
    Task.create!(title: "T-Eingang", creator: @hans, assignee: @hans, commitment: nil)
    Task.create!(title: "T-Heute",   creator: @hans, assignee: @hans, commitment: :today)
    Task.create!(title: "T-Soon",    creator: @hans, assignee: @hans, commitment: :soon)
    Task.create!(title: "T-Later",   creator: @hans, assignee: @hans, commitment: :later)
    state = TaskIndexState.new(params: ActionController::Parameters.new({}), actor: @hans)
    keys = state.sections.map(&:first)
    assert_equal [:inbox, :today, :soon, :later], keys
    assert_equal 1, state.sections.find { |k, _| k == :inbox  }.last.size
    assert_equal 1, state.sections.find { |k, _| k == :today  }.last.size
    assert_equal 1, state.sections.find { |k, _| k == :soon   }.last.size
    assert_equal 1, state.sections.find { |k, _| k == :later  }.last.size
  end

  test "Topic-Sections fuehren 'Ohne Projekt' (nil) zuerst und sortieren alphabetisch" do
    a = Topic.create!(name: "Beta",  slug: "beta-#{SecureRandom.hex(2)}",  creator: @hans)
    b = Topic.create!(name: "Alpha", slug: "alpha-#{SecureRandom.hex(2)}", creator: @hans)
    t_none = Task.create!(title: "OhneTopic", creator: @hans, assignee: @hans)
    t_b    = Task.create!(title: "MitBeta",   creator: @hans, assignee: @hans)
    t_a    = Task.create!(title: "MitAlpha",  creator: @hans, assignee: @hans)
    TaskTopic.create!(task: t_b, topic: a) # Beta
    TaskTopic.create!(task: t_a, topic: b) # Alpha

    state = TaskIndexState.new(
      params: ActionController::Parameters.new(group: "topic"), actor: @hans
    )
    keys = state.topic_sections.map { |topic, _| topic&.name }
    assert_equal [nil, "Alpha", "Beta"], keys
    none_section = state.topic_sections.first.last
    assert_equal ["OhneTopic"], none_section.map(&:title)
  end

  test "trash_count ignoriert nicht eigene Tasks" do
    other = create_human
    grant(other, "Task", %w[create])
    Task.create!(title: "Mein", creator: @hans, assignee: @hans, deleted_at: Time.current)
    Task.create!(title: "Fremd", creator: other, assignee: other, deleted_at: Time.current)
    state = TaskIndexState.new(params: ActionController::Parameters.new({}), actor: @hans)
    assert_equal 1, state.trash_count
  end

  test "delegiert show_done/q/tag/priority/sort/dir an TaskQuery" do
    params = ActionController::Parameters.new(
      show_done: "1", q: "abc", tag: "foo", priority: "high",
      sort: "title", dir: "asc"
    )
    state = TaskIndexState.new(params: params, actor: @hans)
    assert_equal true,    state.show_done
    assert_equal "abc",   state.q
    assert_equal "foo",   state.tag
    assert_equal "high",  state.priority
    assert_equal "title", state.sort
    assert_equal "asc",   state.dir
  end
end
