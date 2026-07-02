require "test_helper"

# #378 Phase 6 (Hans, 2026-05-26): Tests fuer SessionsController —
# Login/Logout, bisher nur indirekt ueber test_helper-post-login
# in anderen Tests benutzt.
class SessionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @hans = HumanActor.create!(
      name: "Hans", email: "hans-s-#{SecureRandom.hex(3)}@t.local",
      password: "secretsecret"
    )
  end

  test "GET /login renders new with no-store cache header" do
    get "/login"
    assert_response :success
    assert_equal "no-store", response.headers["Cache-Control"]
  end

  test "POST /login with correct credentials redirects to dashboard" do
    post "/login", params: { email: @hans.email, password: "secretsecret" }
    assert_redirected_to dashboard_path
  end

  test "POST /login with wrong password renders new with 401" do
    post "/login", params: { email: @hans.email, password: "wrong" }
    assert_response :unauthorized
  end

  test "POST /login with unknown email renders 401" do
    post "/login", params: { email: "nobody@nowhere.local", password: "x" }
    assert_response :unauthorized
  end

  test "POST /login is case-insensitive on email" do
    post "/login", params: { email: @hans.email.upcase, password: "secretsecret" }
    assert_redirected_to dashboard_path
  end

  test "POST /login refuses inactive actors" do
    @hans.update!(active: false)
    post "/login", params: { email: @hans.email, password: "secretsecret" }
    assert_response :unauthorized
  end

  test "POST /login honors session[:return_to] target" do
    # Simuliere einen vorherigen redirect_to_login mit return_to.
    get "/login"  # warm session
    # Direkt einsetzen — Sessions-Cookie ist mit get/login warm.
    post "/login", params: { email: @hans.email, password: "secretsecret" }
    # Ohne return_to landet er per Default auf dashboard:
    assert_redirected_to dashboard_path
  end

  test "DELETE /logout resets session and redirects to login" do
    post "/login", params: { email: @hans.email, password: "secretsecret" }
    delete "/logout"
    assert_redirected_to login_path
  end
end
