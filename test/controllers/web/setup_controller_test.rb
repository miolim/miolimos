require "test_helper"

# #806: First-Run-Onboarding — der Setup-Screen existiert NUR solange kein
# HumanActor existiert; danach ist er hart gesperrt (keine Hintertür).
class SetupControllerTest < ActionDispatch::IntegrationTest
  test "GET /setup renders the first-run form on a virgin instance" do
    assert_equal 0, HumanActor.count
    get "/setup"
    assert_response :ok
    assert_includes @response.body, "human_actor[email]"
  end

  test "GET /login redirects to /setup while no human exists" do
    get "/login"
    assert_redirected_to "/setup"
  end

  test "POST /setup creates the admin with full capabilities and signs in" do
    assert_difference -> { HumanActor.count }, 1 do
      post "/setup", params: { human_actor: {
        name: "Erste Adminin", email: "admin@instanz.example",
        password: "sehrsicher123", password_confirmation: "sehrsicher123"
      } }
    end
    assert_redirected_to "/dashboard"

    admin = HumanActor.last
    assert_equal "admin", admin.role
    assert admin.active?
    # Vollrechte auf der gesamten Standard-Matrix
    CapabilityDefaults::RESOURCE_TYPES.each do |rt|
      assert AccessGate.can?(actor: admin, resource_type: rt, action: "delete"),
             "admin must be able to delete #{rt}"
    end
    # direkt angemeldet: Dashboard erreichbar
    follow_redirect!
    assert_response :ok
  end

  test "POST /setup with mismatched confirmation re-renders with error" do
    assert_no_difference -> { HumanActor.count } do
      post "/setup", params: { human_actor: {
        name: "X", email: "x@y.example",
        password: "sehrsicher123", password_confirmation: "anders12345"
      } }
    end
    assert_response :unprocessable_entity
  end

  test "POST /setup with blank password creates nothing" do
    assert_no_difference -> { HumanActor.count } do
      post "/setup", params: { human_actor: {
        name: "X", email: "x@y.example",
        password: "", password_confirmation: ""
      } }
    end
    assert_response :unprocessable_entity
  end

  test "setup is locked once a human exists" do
    create_human
    get "/setup"
    assert_redirected_to "/login"
    assert_no_difference -> { HumanActor.count } do
      post "/setup", params: { human_actor: {
        name: "Eindringling", email: "evil@x.example",
        password: "sehrsicher123", password_confirmation: "sehrsicher123"
      } }
    end
    assert_redirected_to "/login"
  end

  test "GET /login renders normally once a human exists" do
    create_human
    get "/login"
    assert_response :ok
  end
end
