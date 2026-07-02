require "test_helper"

class LoginFlowTest < ActionDispatch::IntegrationTest
  setup do
    @hans = HumanActor.create!(
      name: "Hans", email: "hans-login-#{SecureRandom.hex(3)}@t.local",
      password: "secretsecret"
    )
    grant(@hans, "Task", %w[read])
    grant(@hans, "Topic", %w[read])
  end

  test "GET /dashboard redirects to /login when not signed in" do
    get "/dashboard"
    assert_redirected_to "/login"
  end

  test "POST /login with valid credentials redirects to saved return_to" do
    get "/dashboard"
    follow_redirect!
    post "/login", params: { email: @hans.email, password: "secretsecret" }
    assert_redirected_to "/dashboard"
  end

  test "POST /login with invalid credentials re-renders with 401" do
    post "/login", params: { email: @hans.email, password: "wrong" }
    assert_response :unauthorized
  end

  test "inactive HumanActor cannot log in" do
    @hans.update!(active: false)
    post "/login", params: { email: @hans.email, password: "secretsecret" }
    assert_response :unauthorized
  end

  test "DELETE /logout clears session and redirects to /login" do
    post "/login", params: { email: @hans.email, password: "secretsecret" }
    follow_redirect!
    delete "/logout"
    assert_redirected_to "/login"

    get "/dashboard"
    assert_redirected_to "/login"
  end

  test "AgentActor cannot log in via web (HumanActor-only)" do
    agent = AgentActor.create!(name: "Bot-#{SecureRandom.hex(3)}", description: "x")
    agent.update!(password_digest: BCrypt::Password.create("secretsecret"))

    post "/login", params: { email: "whatever", password: "secretsecret" }
    assert_response :unauthorized
  end
end
