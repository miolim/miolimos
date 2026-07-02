require "test_helper"

class Api::V1::CommunicationsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @agent = AgentActor.create!(name: "cm-#{SecureRandom.hex(3)}", description: "t")
    grant(@agent, "Communication", %w[read update])
    @headers = { "Authorization" => "Bearer #{@agent.api_token}" }
  end

  def build_email(**overrides)
    Email.create!({
      subject: "Hi", body: "b", direction: :inbound,
      sent_at: Time.current,
      external_id: "gm-#{SecureRandom.hex(4)}"
    }.merge(overrides))
  end

  test "POST /communications is not routed (no create)" do
    post "/api/v1/communications", params: { subject: "x" }, headers: @headers
    assert_includes [404, 405], response.status
  end

  test "index filters by direction" do
    inb = build_email(direction: :inbound)
    out = build_email(direction: :outbound)

    get "/api/v1/communications", params: { direction: "inbound" }, headers: @headers
    ids = JSON.parse(response.body)["data"].map { |c| c["id"] }
    assert_includes ids, inb.id
    refute_includes ids, out.id
  end

  test "index filters by topic_id" do
    creator = create_human
    topic = Topic.create!(name: "T", slug: "t-#{SecureRandom.hex(3)}", creator: creator)
    matching = build_email
    non_matching = build_email
    CommunicationTopic.create!(communication: matching, topic: topic)

    get "/api/v1/communications", params: { topic_id: topic.id }, headers: @headers
    ids = JSON.parse(response.body)["data"].map { |c| c["id"] }
    assert_equal [matching.id], ids
  end

  test "show" do
    e = build_email(subject: "Show me")
    get "/api/v1/communications/#{e.id}", headers: @headers
    body = JSON.parse(response.body)["data"]
    assert_equal "Show me", body["subject"]
    assert_equal "Email", body["type"]
  end

  test "index filters by mentioned_uuid" do
    alice = KnowledgeItem.create!(
      uuid: SecureRandom.uuid, title: "Alice D",
      item_type: :person,
      first_name: "A", last_name: "D",
      file_path: "knowledge/people/alice-#{SecureRandom.hex(3)}.md",
      content_hash: SecureRandom.hex(32),
      file_created_at: Time.current, file_updated_at: Time.current,
      indexed_at: Time.current
    )
    hit   = build_email
    miss  = build_email
    CommunicationMention.create!(communication: hit, mentioned_uuid: alice.uuid, role: "sender")

    get "/api/v1/communications", params: { mentioned_uuid: alice.uuid }, headers: @headers
    ids = JSON.parse(response.body)["data"].map { |c| c["id"] }
    assert_equal [hit.id], ids
    refute_includes ids, miss.id
  end

  test "index filters by oauth_credential_id" do
    cred = OauthCredential.create!(
      actor: create_human, provider: "google",
      email_address: "filt-#{SecureRandom.hex(3)}@x.io",
      access_token: "a", refresh_token: "r",
      expires_at: 1.hour.from_now, scopes: []
    )
    hit  = build_email(oauth_credential: cred)
    miss = build_email

    get "/api/v1/communications", params: { oauth_credential_id: cred.id }, headers: @headers
    ids = JSON.parse(response.body)["data"].map { |c| c["id"] }
    assert_equal [hit.id], ids
    refute_includes ids, miss.id
  end

  test "nested POST /topics links a communication to a topic" do
    creator = create_human
    topic = Topic.create!(name: "T", slug: "t-#{SecureRandom.hex(3)}", creator: creator)
    e = build_email

    post "/api/v1/communications/#{e.id}/topics", params: { topic_id: topic.id }, headers: @headers
    assert_response :created
    assert CommunicationTopic.exists?(communication: e, topic: topic)
  end

  test "nested DELETE /topics/:id unlinks" do
    creator = create_human
    topic = Topic.create!(name: "T", slug: "t-#{SecureRandom.hex(3)}", creator: creator)
    e = build_email
    CommunicationTopic.create!(communication: e, topic: topic)

    delete "/api/v1/communications/#{e.id}/topics/#{topic.id}", headers: @headers
    assert_response :no_content
    refute CommunicationTopic.exists?(communication: e, topic: topic)
  end

  test "nested operations require update on Communication" do
    read_only = AgentActor.create!(name: "rr-#{SecureRandom.hex(3)}", description: "t")
    grant(read_only, "Communication", %w[read])

    creator = create_human
    topic = Topic.create!(name: "T", slug: "t-#{SecureRandom.hex(3)}", creator: creator)
    e = build_email

    post "/api/v1/communications/#{e.id}/topics",
         params: { topic_id: topic.id },
         headers: { "Authorization" => "Bearer #{read_only.api_token}" }
    assert_response :forbidden
  end
end
