require "test_helper"

class CommunicationsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @hans = HumanActor.create!(
      name: "Hans", email: "hans-c-#{SecureRandom.hex(3)}@t.local",
      password: "secretsecret", role: :admin
    )
    grant(@hans, "Communication", %w[read update])
    grant(@hans, "Task",          %w[read create])
    grant(@hans, "Awaiting",      %w[read create])
    grant(@hans, "Topic",         %w[read])
    grant(@hans, "Contact",       %w[read])

    post "/login", params: { email: @hans.email, password: "secretsecret" }
  end

  def build_comm(attrs = {})
    Email.create!({
      external_id: "msg-#{SecureRandom.hex(4)}",
      subject:     "Hallo",
      sent_at:     Time.current,
      direction:   :inbound
    }.merge(attrs))
  end

  test "GET /communications lists communications" do
    c = build_comm(subject: "Angebot Ring")
    get "/communications"
    assert_response :success
    assert_includes @response.body, "Angebot Ring"
  end

  test "GET /communications?direction=outbound filters" do
    build_comm(subject: "INBOX-X", direction: :inbound)
    build_comm(subject: "SENT-Y",  direction: :outbound)
    get "/communications", params: { direction: "outbound" }
    assert_includes @response.body, "SENT-Y"
    refute_includes @response.body, "INBOX-X"
  end

  test "GET /communications/:id leitet auf Stack-Seite mit Detail-Blade um" do
    c = build_comm(subject: "Detail-Test-Z")
    get "/communications/#{c.id}"
    # #163 Phase 6c: /communications ist eine Blade-Stack-Seite,
    # Vollaufrufe von /communications/:id redirecten zur Stack-URL.
    assert_redirected_to communications_path(stack: "list:communications,communication:#{c.id}")
    follow_redirect!
    assert_response :success
    assert_includes @response.body, "Detail-Test-Z"
  end

  # #1018 (Hans, 2026-07-16): Batch-Edit von Kommunikationen.
  test "POST /communications/bulk_update ordnet allen ids das Thema zu" do
    topic = Topic.create!(name: "BulkTopic", slug: "bulk-#{SecureRandom.hex(2)}", creator: @hans)
    c1 = build_comm(subject: "BULK-A")
    c2 = build_comm(subject: "BULK-B")
    c3 = build_comm(subject: "BULK-C")

    post bulk_update_communications_path,
         params: { ids: [c1.id, c2.id], add_topic_id: topic.id },
         as: :turbo_stream
    assert_response :success

    assert_includes c1.reload.topics, topic
    assert_includes c2.reload.topics, topic
    assert_empty    c3.reload.topics
    # Zuordnung ist idempotent (find_or_create).
    post bulk_update_communications_path,
         params: { ids: [c1.id], add_topic_id: topic.id },
         as: :turbo_stream
    assert_equal 1, c1.reload.communication_topics.count
  end

  test "POST /communications/bulk_update mode=delete loescht die ids" do
    grant(@hans, "Communication", %w[read update delete])
    c1 = build_comm(subject: "DEL-A")
    c2 = build_comm(subject: "DEL-B")
    c3 = build_comm(subject: "KEEP-C")

    assert_difference -> { Communication.count }, -2 do
      post bulk_update_communications_path,
           params: { ids: [c1.id, c2.id], mode: "delete" },
           as: :turbo_stream
    end
    assert_response :success
    assert_includes @response.body, "communication_row_#{c1.id}"
    assert Communication.exists?(c3.id)
  end

  test "POST /communications/bulk_update ohne ids antwortet mit Toast" do
    post bulk_update_communications_path, params: { mode: "delete" }, as: :turbo_stream
    assert_response :success
    assert_match(/ausgew/i, @response.body)
  end

  test "POST /communications/:id/create_task creates a task" do
    c = build_comm(subject: "Wichtige Sache")
    assert_difference -> { Task.count }, 1 do
      post "/communications/#{c.id}/create_task"
    end
    task = Task.order(:id).last
    assert_equal c.id, task.communication_id
    assert_redirected_to task_path(task)
  end

  test "POST /communications/:id/accept_topic_suggestion links the topic" do
    topic = Topic.create!(name: "T", slug: "t-#{SecureRandom.hex(3)}", creator: @hans)
    c = build_comm(subject: "Angebot")
    c.update_columns(suggested_topic_id: topic.id, suggested_topic_score: 0.55,
                     suggested_topic_decided_at: nil)

    post "/communications/#{c.id}/accept_topic_suggestion"
    assert_includes c.reload.topics, topic
    assert_not_nil c.suggested_topic_decided_at
  end

  test "POST /communications/:id/reject_topic_suggestion marks decided without linking" do
    topic = Topic.create!(name: "T", slug: "t-#{SecureRandom.hex(3)}", creator: @hans)
    c = build_comm(subject: "Spam?")
    c.update_columns(suggested_topic_id: topic.id, suggested_topic_score: 0.5,
                     suggested_topic_decided_at: nil)

    post "/communications/#{c.id}/reject_topic_suggestion"
    assert_empty c.reload.topics
    assert_not_nil c.suggested_topic_decided_at
  end

  test "POST /communications/:id/create_awaiting creates awaiting with topics" do
    topic = Topic.create!(name: "T", slug: "t-#{SecureRandom.hex(3)}", creator: @hans)
    c = build_comm(subject: "Follow-up?")
    CommunicationTopic.create!(communication: c, topic: topic)

    assert_difference -> { Awaiting.count }, 1 do
      post "/communications/#{c.id}/create_awaiting",
           params: { description: "Antwort?" }
    end
    a = Awaiting.order(:id).last
    assert_equal c.id, a.communication_id
    assert_includes a.topics, topic
    assert_equal "Antwort?", a.title
  end
end
