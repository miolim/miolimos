require "test_helper"

class Api::V1::BaseAuthTest < ActionDispatch::IntegrationTest
  setup do
    @hans = create_human
    grant(@hans, "Task", %w[read create update delete])

    @token = AgentActor.create!(name: "Bot-#{SecureRandom.hex(3)}", description: "test").tap do |a|
      grant(a, "Task", %w[read])
    end
  end

  test "missing Authorization header returns 401" do
    get "/api/v1/tasks"
    assert_response :unauthorized
    body = JSON.parse(response.body)
    assert_equal "invalid_token", body["code"]
  end

  test "malformed Bearer header returns 401" do
    get "/api/v1/tasks", headers: { "Authorization" => "Token abc" }
    assert_response :unauthorized
  end

  test "unknown token returns 401" do
    get "/api/v1/tasks", headers: { "Authorization" => "Bearer nonsense" }
    assert_response :unauthorized
  end

  test "inactive actor cannot authenticate even with valid token" do
    @token.update!(active: false)
    get "/api/v1/tasks", headers: { "Authorization" => "Bearer #{@token.api_token}" }
    assert_response :unauthorized
  end

  test "valid token with read capability succeeds" do
    get "/api/v1/tasks", headers: { "Authorization" => "Bearer #{@token.api_token}" }
    assert_response :success
    body = JSON.parse(response.body)
    assert body.key?("data")
    assert body.key?("meta")
  end

  test "valid token without capability returns 403" do
    stripped = AgentActor.create!(name: "No-Caps-#{SecureRandom.hex(3)}", description: "test")
    get "/api/v1/tasks", headers: { "Authorization" => "Bearer #{stripped.api_token}" }
    assert_response :forbidden
    body = JSON.parse(response.body)
    assert_equal "forbidden", body["code"]
  end

  test "valid token with deny overrides allow" do
    grant(@token, "Task", %w[read], effect: :deny)
    get "/api/v1/tasks", headers: { "Authorization" => "Bearer #{@token.api_token}" }
    assert_response :forbidden
  end
end
