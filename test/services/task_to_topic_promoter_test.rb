require "test_helper"

class TaskToTopicPromoterTest < ActiveSupport::TestCase
  setup do
    @hans = create_human
    grant(@hans, "Task",  %w[read create update delete])
    grant(@hans, "Topic", %w[read create update delete])
    grant(@hans, "KnowledgeItem", %w[read create update delete])
    grant(@hans, "Awaiting", %w[read create update delete])
  end

  test "legt neues Topic mit Title/Description/Slug aus der Task an" do
    task = create_task(creator: @hans, title: "Marketing Kampagne Q3", description: "Plan für Q3")
    topic = TaskToTopicPromoter.call(task, actor: @hans)
    assert topic.persisted?
    assert_equal "Marketing Kampagne Q3", topic.name
    assert_equal "marketing-kampagne-q3", topic.slug
    assert_equal "Plan für Q3", topic.description
    assert_equal @hans.id, topic.creator_id
  end

  test "hängt Subtasks als Top-Level-Tasks ans neue Topic" do
    parent = create_task(creator: @hans, title: "Großes Projekt")
    sub1   = create_task(creator: @hans, title: "Sub 1", parent_id: parent.id)
    sub2   = create_task(creator: @hans, title: "Sub 2", parent_id: parent.id)

    topic = TaskToTopicPromoter.call(parent, actor: @hans)
    [sub1, sub2].each(&:reload)
    assert_nil sub1.parent_id
    assert_nil sub2.parent_id
    assert_includes topic.tasks.pluck(:id), sub1.id
    assert_includes topic.tasks.pluck(:id), sub2.id
  end

  test "transferiert Awaitings ans neue Topic" do
    task = create_task(creator: @hans, title: "Wachstaks")
    awaiting = Awaiting.create!(title: "Antwort?", task: task, creator: @hans,
                                follow_up_at: Date.today + 3)
    topic = TaskToTopicPromoter.call(task, actor: @hans)
    assert_includes topic.awaitings.pluck(:id), awaiting.id
  end

  test "schließt die Original-Task mit Verweis aufs neue Topic" do
    task = create_task(creator: @hans, title: "Foo", description: "Original-Beschreibung")
    topic = TaskToTopicPromoter.call(task, actor: @hans)
    task.reload
    assert_equal "done", task.status
    assert_not_nil task.completed_at
    assert_match(/umgewandelt in Thema/i, task.description)
    assert_match(/topics\/#{topic.slug}/, task.description)
    assert_match(/Original-Beschreibung/, task.description)
  end

  test "Slug-Kollision wird durchnummeriert" do
    Topic.create!(slug: "foo", name: "Foo", creator: @hans, status: :active)
    task = create_task(creator: @hans, title: "Foo")
    topic = TaskToTopicPromoter.call(task, actor: @hans)
    assert_equal "foo-2", topic.slug
  end
end
