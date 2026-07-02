require "test_helper"

class Api::V1::InboxItemsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @agent = AgentActor.create!(name: "Bot-#{SecureRandom.hex(3)}", description: "test")
    grant(@agent, "InboxItem", %w[read create update])
    @auth = { "Authorization" => "Bearer #{@agent.api_token}" }
  end

  test "GET index lists active items in newest-first order" do
    older = InboxItem.create!(creator: @agent, source_kind: "text", raw_content: "a",
                              status: "pending", title: "older", created_at: 2.minutes.ago)
    newer = InboxItem.create!(creator: @agent, source_kind: "text", raw_content: "b",
                              status: "pending", title: "newer")
    InboxItem.create!(creator: @agent, source_kind: "text", raw_content: "c",
                      status: "archived", title: "archived")
    get "/api/v1/inbox_items", headers: @auth
    assert_response :ok
    titles = JSON.parse(response.body)["data"].map { |i| i["title"] }
    assert_equal "newer", titles.first
    assert_includes titles, older.title
    refute_includes titles, "archived"
  end

  test "GET index filters by status" do
    InboxItem.create!(creator: @agent, source_kind: "text", raw_content: "x",
                      status: "pending", title: "p1")
    failed = InboxItem.create!(creator: @agent, source_kind: "text", raw_content: "y",
                               status: "failed", title: "f1")
    get "/api/v1/inbox_items", params: { status: "failed" }, headers: @auth
    body = JSON.parse(response.body)
    ids = body["data"].map { |i| i["id"] }
    assert_equal [failed.id], ids
  end

  test "GET show returns serialized item" do
    item = InboxItem.create!(creator: @agent, source_kind: "web_url",
                             source_url: "https://example.com/x",
                             status: "pending", title: "show me")
    get "/api/v1/inbox_items/#{item.id}", headers: @auth
    assert_response :ok
    body = JSON.parse(response.body)
    assert_equal item.id,         body["data"]["id"]
    assert_equal "show me",       body["data"]["title"]
    assert_equal "web_url",       body["data"]["source_kind"]
  end

  test "POST create infers source_kind=web_url for non-youtube URLs" do
    assert_difference -> { InboxItem.count }, 1 do
      post "/api/v1/inbox_items",
           params: { source_url: "https://example.com/article" }, headers: @auth
    end
    assert_response :created
    assert_equal "web_url", InboxItem.last.source_kind
    assert_equal @agent.id, InboxItem.last.creator_id
  end

  test "POST create infers source_kind=youtube_url for youtube URLs" do
    post "/api/v1/inbox_items",
         params: { source_url: "https://youtu.be/abc123def45" }, headers: @auth
    assert_equal "youtube_url", InboxItem.last.source_kind
  end

  test "POST create with raw_content infers source_kind=markdown" do
    post "/api/v1/inbox_items",
         params: { raw_content: "# Note" }, headers: @auth
    assert_equal "markdown", InboxItem.last.source_kind
  end

  test "POST without create capability returns 403" do
    no_caps = AgentActor.create!(name: "No-#{SecureRandom.hex(3)}", description: "x")
    grant(no_caps, "InboxItem", %w[read])
    post "/api/v1/inbox_items",
         params: { raw_content: "hi" },
         headers: { "Authorization" => "Bearer #{no_caps.api_token}" }
    assert_response :forbidden
  end
end

class Api::V1::ContactsGoneTest < ActionDispatch::IntegrationTest
  setup do
    @agent = AgentActor.create!(name: "Bot-#{SecureRandom.hex(3)}", description: "test")
    grant(@agent, "KnowledgeItem", %w[read])
    grant(@agent, "Contact",       %w[read])
    @auth = { "Authorization" => "Bearer #{@agent.api_token}" }
  end

  test "GET /api/v1/contacts returns 410 Gone with redirect hint" do
    get "/api/v1/contacts", headers: @auth
    assert_response :gone
    body = JSON.parse(response.body)
    assert_match(/knowledge_items/, body["error"])
  end

  test "GET /api/v1/contacts/:id also returns 410" do
    get "/api/v1/contacts/123", headers: @auth
    assert_response :gone
  end
end
