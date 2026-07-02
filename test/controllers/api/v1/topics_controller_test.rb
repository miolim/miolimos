require "test_helper"

class Api::V1::TopicsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @creator = create_human
    @agent = AgentActor.create!(name: "t-#{SecureRandom.hex(3)}", description: "t")
    grant(@agent, "Topic", %w[read create update delete])
    @headers = { "Authorization" => "Bearer #{@agent.api_token}" }
  end

  test "index filters by status and template" do
    active_reg  = Topic.create!(name: "Reg", slug: "reg-#{SecureRandom.hex(3)}", creator: @creator, status: :active, template: false)
    paused      = Topic.create!(name: "Pau", slug: "pau-#{SecureRandom.hex(3)}", creator: @creator, status: :paused, template: false)
    template    = Topic.create!(name: "Tmpl", slug: "tmpl-#{SecureRandom.hex(3)}", creator: @creator, status: :active, template: true)

    get "/api/v1/topics", params: { status: "active", template: false }, headers: @headers
    ids = JSON.parse(response.body)["data"].map { |t| t["id"] }
    assert_includes ids, active_reg.id
    refute_includes ids, paused.id
    refute_includes ids, template.id
  end

  test "create uses current_actor as creator" do
    post "/api/v1/topics",
         params: { name: "From API", slug: "from-api-#{SecureRandom.hex(3)}" },
         headers: @headers
    assert_response :created
    body = JSON.parse(response.body)["data"]
    assert_equal @agent.id, body["creator_id"]
  end

  test "instantiate on a template creates a new non-template topic" do
    template = Topic.create!(name: "PV-Tmpl", slug: "pv-tmpl-#{SecureRandom.hex(3)}",
                             creator: @creator, template: true)
    Task.create!(title: "Site visit", creator: @creator).tap do |t|
      TaskTopic.create!(task: t, topic: template, position: 1)
    end

    post "/api/v1/topics/#{template.id}/instantiate",
         params: { new_name: "Customer X" },
         headers: @headers
    assert_response :created

    new_topic = Topic.find_by(name: "Customer X")
    refute_nil new_topic
    refute new_topic.template?
    assert_equal 1, new_topic.tasks.count
  end

  test "instantiate on a non-template returns 422" do
    regular = Topic.create!(name: "Reg", slug: "reg-#{SecureRandom.hex(3)}", creator: @creator, template: false)
    post "/api/v1/topics/#{regular.id}/instantiate", params: { new_name: "nope" }, headers: @headers
    assert_response :unprocessable_entity
    assert_equal "not_a_template", JSON.parse(response.body)["code"]
  end

  test "show returns one topic" do
    t = Topic.create!(name: "Show me", slug: "show-#{SecureRandom.hex(3)}", creator: @creator)
    get "/api/v1/topics/#{t.id}", headers: @headers
    assert_response :success
    assert_equal t.id, JSON.parse(response.body)["data"]["id"]
  end

  test "show 404 for unknown id" do
    get "/api/v1/topics/999999", headers: @headers
    assert_response :not_found
  end

  test "update PATCH changes fields" do
    t = Topic.create!(name: "Before", slug: "upd-#{SecureRandom.hex(3)}", creator: @creator)
    patch "/api/v1/topics/#{t.id}", params: { name: "After", status: "paused" }, headers: @headers
    assert_response :success
    assert_equal "After", t.reload.name
    assert t.paused?
  end

  test "update requires update capability (not create)" do
    ro = AgentActor.create!(name: "ro-#{SecureRandom.hex(3)}", description: "t")
    grant(ro, "Topic", %w[read create])  # no update

    t = Topic.create!(name: "Before", slug: "upd-#{SecureRandom.hex(3)}", creator: @creator)
    patch "/api/v1/topics/#{t.id}", params: { name: "After" },
          headers: { "Authorization" => "Bearer #{ro.api_token}" }
    assert_response :forbidden
  end

  test "instantiate requires create capability" do
    bot = AgentActor.create!(name: "ro-#{SecureRandom.hex(3)}", description: "t")
    grant(bot, "Topic", %w[read])  # kein create
    template = Topic.create!(name: "T", slug: "t-#{SecureRandom.hex(3)}", creator: @creator, template: true)

    post "/api/v1/topics/#{template.id}/instantiate",
         params: { new_name: "x" },
         headers: { "Authorization" => "Bearer #{bot.api_token}" }
    assert_response :forbidden
  end
end
