require "test_helper"

class TopicTemplateServiceTest < ActiveSupport::TestCase
  setup do
    @creator = create_human
    @team    = create_team
    TeamMembership.create!(team: @team, actor: @creator, role: :owner)

    @template = create_topic(creator: @creator, name: "PV-Template", slug: "pv-template-#{SecureRandom.hex(2)}", template: true, team: @team)

    @t1 = create_task(creator: @creator, title: "Site visit",  priority: :high)
    @t2 = create_task(creator: @creator, title: "Quote",       priority: :normal)
    @t3 = create_task(creator: @creator, title: "Contract",    priority: :normal)
    @sub_of_t3 = create_task(creator: @creator, title: "NDA",  parent: @t3)

    TaskTopic.create!(task: @t1, topic: @template, position: 1)
    TaskTopic.create!(task: @t2, topic: @template, position: 2)
    TaskTopic.create!(task: @t3, topic: @template, position: 3)
    # Subtask is intentionally NOT directly in the topic but is part of the hierarchy

    TaskDependency.create!(predecessor: @t1, successor: @t2)
    TaskDependency.create!(predecessor: @t2, successor: @t3)

    # Pre-set assignees on template so we can verify they get nil'd
    @t1.update!(assignee: @creator)
  end

  test "rejects non-template topics" do
    regular = create_topic(creator: @creator)
    assert_raises(TopicTemplateService::NotATemplateError) do
      TopicTemplateService.instantiate(regular, new_name: "x", creator: @creator)
    end
  end

  test "creates a non-template topic with copied tasks" do
    new_topic = TopicTemplateService.instantiate(@template, new_name: "Customer A", creator: @creator, team_id: @team.id)

    refute new_topic.template?
    assert_equal "Customer A", new_topic.name
    assert_equal 3, new_topic.tasks.count

    cloned_titles = new_topic.ordered_tasks.pluck(:title)
    assert_equal ["Site visit", "Quote", "Contract"], cloned_titles
  end

  test "does not mutate or reuse original template tasks" do
    original_ids = @template.tasks.pluck(:id).sort
    new_topic    = TopicTemplateService.instantiate(@template, new_name: "B", creator: @creator)

    assert_equal original_ids, @template.tasks.pluck(:id).sort
    assert_empty(original_ids & new_topic.tasks.pluck(:id), "cloned tasks must have new IDs")
  end

  test "clones subtask hierarchy (parent_id remapped)" do
    TaskTopic.create!(task: @sub_of_t3, topic: @template, position: 4)

    new_topic = TopicTemplateService.instantiate(@template, new_name: "C", creator: @creator)

    cloned_contract = new_topic.tasks.find_by(title: "Contract")
    cloned_nda      = new_topic.tasks.find_by(title: "NDA")

    assert_not_nil cloned_contract
    assert_not_nil cloned_nda
    assert_equal cloned_contract.id, cloned_nda.parent_id
  end

  test "clones all dependencies with remapped ids" do
    new_topic = TopicTemplateService.instantiate(@template, new_name: "D", creator: @creator)

    new_ids = new_topic.tasks.pluck(:id)
    cloned_deps = TaskDependency.where(predecessor_id: new_ids, successor_id: new_ids)
    assert_equal 2, cloned_deps.count
  end

  test "preserves task_topics position" do
    new_topic = TopicTemplateService.instantiate(@template, new_name: "E", creator: @creator)
    positions = new_topic.task_topics.order(:position).pluck(:position)
    assert_equal [1, 2, 3], positions
  end

  test "clones tasks with assignee_id set to nil" do
    new_topic = TopicTemplateService.instantiate(@template, new_name: "F", creator: @creator)
    new_topic.tasks.each do |t|
      assert_nil t.assignee_id, "cloned task should have no assignee"
    end
  end

  test "new topic uses the passed creator" do
    other = create_human
    new_topic = TopicTemplateService.instantiate(@template, new_name: "G", creator: other)
    assert_equal other, new_topic.creator
    new_topic.tasks.each { |t| assert_equal other, t.creator }
  end

  test "slug collision is resolved with a counter suffix" do
    TopicTemplateService.instantiate(@template, new_name: "Duplicate", creator: @creator)
    second = TopicTemplateService.instantiate(@template, new_name: "Duplicate", creator: @creator)
    assert_match(/\Aduplicate(-\d+)?\z/, second.slug)
    refute_equal "duplicate", second.slug
  end

  test "rolls back on error" do
    before_topic_count = Topic.count
    before_task_count  = Task.count

    # Force a failure mid-way by stubbing TaskTopic.create! on second invocation
    original = TaskTopic.method(:create!)
    calls = 0
    TaskTopic.define_singleton_method(:create!) do |*args, **kw|
      calls += 1
      raise ActiveRecord::RecordInvalid.new(TaskTopic.new) if calls == 2
      original.call(*args, **kw)
    end

    assert_raises(ActiveRecord::RecordInvalid) do
      TopicTemplateService.instantiate(@template, new_name: "Rolls back", creator: @creator)
    end

    assert_equal before_topic_count, Topic.count, "new Topic must be rolled back"
    assert_equal before_task_count,  Task.count,  "cloned Tasks must be rolled back"
  ensure
    TaskTopic.singleton_class.send(:remove_method, :create!) rescue nil
  end
end
