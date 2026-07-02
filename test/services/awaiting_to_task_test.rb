require "test_helper"

class AwaitingToTaskTest < ActiveSupport::TestCase
  setup do
    @hans = create_human
  end

  test "creates task, copies topics with position and contact, resolves awaiting" do
    topic   = create_topic(creator: @hans)
    contact_ki = KnowledgeItem.create!(
      uuid: SecureRandom.uuid, title: "A B",
      item_type: :person,
      first_name: "A", last_name: "B",
      file_path: "knowledge/people/a-b-#{SecureRandom.hex(3)}.md",
      content_hash: SecureRandom.hex(32),
      file_created_at: Time.current, file_updated_at: Time.current,
      indexed_at: Time.current
    )
    awaiting = Awaiting.create!(creator: @hans, title: "warte", follow_up_at: Date.today + 3,
                                contact_ki: contact_ki)
    AwaitingTopic.create!(awaiting: awaiting, topic: topic)

    task = AwaitingToTask.call(awaiting: awaiting, creator: @hans, title: "Do it")

    assert task.open?
    assert_equal "Do it", task.title
    assert_includes task.topics, topic
    assert_includes task.mentioned_kis, contact_ki
    assert_equal 1, TaskTopic.find_by(task: task, topic: topic).position

    awaiting.reload
    assert awaiting.resolved?
    assert_equal "Aufgabe erstellt: Do it", awaiting.resolution_note
  end

  test "creates task_dependency when awaiting has a trigger task" do
    trigger = Task.create!(title: "trigger", creator: @hans)
    awaiting = Awaiting.create!(creator: @hans, title: "x", follow_up_at: Date.today + 3,
                                task: trigger)

    task = AwaitingToTask.call(awaiting: awaiting, creator: @hans, title: "next")
    assert TaskDependency.exists?(predecessor: trigger, successor: task)
  end

  test "rolls back on failure" do
    awaiting = Awaiting.create!(creator: @hans, title: "x", follow_up_at: Date.today + 3)
    before_count = Task.count

    # Title ist required → leerer Titel wirft RecordInvalid
    assert_raises(ActiveRecord::RecordInvalid) do
      AwaitingToTask.call(awaiting: awaiting, creator: @hans, title: "")
    end
    assert_equal before_count, Task.count
    refute awaiting.reload.resolved?
  end
end
