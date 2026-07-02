require "test_helper"

class CommunicationTopicsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @hans = HumanActor.create!(
      name: "Hans", email: "hans-ct-#{SecureRandom.hex(3)}@t.local",
      password: "secretsecret"
    )
    grant(@hans, "Communication", %w[read update])
    grant(@hans, "Topic",         %w[read])

    post "/login", params: { email: @hans.email, password: "secretsecret" }
  end

  def build_comm
    Email.create!(external_id: "msg-#{SecureRandom.hex(4)}",
                  subject: "Hallo", sent_at: Time.current, direction: :inbound)
  end

  test "POST /communications/:id/topics adds the topic" do
    c = build_comm
    topic = Topic.create!(name: "T", slug: "t-#{SecureRandom.hex(3)}", creator: @hans)
    post "/communications/#{c.id}/topics", params: { topic_id: topic.id }
    assert_includes c.reload.topics, topic
  end

  test "DELETE /communications/:id/topics/:slug removes the topic" do
    c = build_comm
    topic = Topic.create!(name: "T", slug: "t-#{SecureRandom.hex(3)}", creator: @hans)
    CommunicationTopic.create!(communication: c, topic: topic)
    delete "/communications/#{c.id}/topics/#{topic.slug}"
    assert_empty c.reload.topics
  end
end
