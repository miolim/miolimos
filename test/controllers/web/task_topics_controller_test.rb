require "test_helper"

# #378 Phase 7 (Hans, 2026-05-26): Tests fuer TaskTopicsController —
# Picker-Subresource, nutzt NestedTopicAssignment-Concern mit Position.
class TaskTopicsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @hans = HumanActor.create!(
      name: "Hans", email: "hans-tt-#{SecureRandom.hex(3)}@t.local",
      password: "secretsecret"
    )
    grant(@hans, "Task",  %w[read create update delete])
    grant(@hans, "Topic", %w[read create update])
    post "/login", params: { email: @hans.email, password: "secretsecret" }
  end

  test "POST /tasks/:id/topics links existing topic via slug" do
    task  = create_task(creator: @hans)
    topic = Topic.create!(name: "T", slug: "t-#{SecureRandom.hex(3)}", creator: @hans)
    post "/tasks/#{task.id}/topics", params: { topic_id: topic.slug }
    assert_includes task.reload.topics, topic
  end

  test "POST /tasks/:id/topics with create_with quick-creates topic" do
    task = create_task(creator: @hans)
    assert_difference -> { Topic.count }, 1 do
      post "/tasks/#{task.id}/topics", params: { create_with: "Frisches Thema" }
    end
    topic = Topic.find_by(name: "Frisches Thema")
    assert_includes task.reload.topics, topic
  end

  test "POST /tasks/:id/topics is idempotent on same link" do
    task  = create_task(creator: @hans)
    topic = Topic.create!(name: "T", slug: "t-#{SecureRandom.hex(3)}", creator: @hans)
    post "/tasks/#{task.id}/topics", params: { topic_id: topic.slug }
    assert_no_difference -> { TaskTopic.count } do
      post "/tasks/#{task.id}/topics", params: { topic_id: topic.slug }
    end
  end

  test "DELETE /tasks/:id/topics/:slug removes the link and emits toast" do
    task  = create_task(creator: @hans)
    topic = Topic.create!(name: "Weg", slug: "weg-#{SecureRandom.hex(3)}", creator: @hans)
    TaskTopic.create!(task: task, topic: topic, position: 1)
    delete "/tasks/#{task.id}/topics/#{topic.slug}",
           headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_response :success
    assert_empty task.reload.topics
    assert_match(/Thema &#39;Weg&#39; entfernt|Thema 'Weg' entfernt/, response.body)
  end
end
