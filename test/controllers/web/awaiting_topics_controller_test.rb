require "test_helper"

# #378 Phase 7 (Hans, 2026-05-26): Tests fuer AwaitingTopicsController —
# Picker-Subresource, nutzt NestedTopicAssignment-Concern (ohne Position).
class AwaitingTopicsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @hans = HumanActor.create!(
      name: "Hans", email: "hans-at-#{SecureRandom.hex(3)}@t.local",
      password: "secretsecret"
    )
    grant(@hans, "Awaiting", %w[read create update delete])
    grant(@hans, "Topic",    %w[read create update])
    @awaiting = Awaiting.create!(creator: @hans, title: "Awaiting-#{SecureRandom.hex(3)}",
                                   follow_up_at: 1.week.from_now)
    post "/login", params: { email: @hans.email, password: "secretsecret" }
  end

  test "POST /awaitings/:id/topics links existing topic" do
    topic = Topic.create!(name: "T", slug: "at-#{SecureRandom.hex(3)}", creator: @hans)
    post "/awaitings/#{@awaiting.id}/topics", params: { topic_id: topic.slug }
    assert_includes @awaiting.reload.topics, topic
  end

  test "POST /awaitings/:id/topics quick-creates new topic via create_with" do
    assert_difference -> { Topic.count }, 1 do
      post "/awaitings/#{@awaiting.id}/topics", params: { create_with: "Neues Awaiting-Thema" }
    end
    assert_includes @awaiting.reload.topics.pluck(:name), "Neues Awaiting-Thema"
  end

  test "DELETE removes the link" do
    topic = Topic.create!(name: "Z", slug: "z-#{SecureRandom.hex(3)}", creator: @hans)
    AwaitingTopic.create!(awaiting: @awaiting, topic: topic)
    delete "/awaitings/#{@awaiting.id}/topics/#{topic.slug}",
           headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_response :success
    assert_empty @awaiting.reload.topics
  end
end
