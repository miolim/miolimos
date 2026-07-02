require "test_helper"

# #203: Coverage fuer den Settings-Root-Redirect.
class SettingsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @hans = HumanActor.create!(name: "Hans",
                                email: "hans-set-#{SecureRandom.hex(3)}@t.local",
                                password: "secretsecret")
    grant(@hans, "Actor", %w[read])   # #613: Settings-Stack gated als Actor
    post "/login", params: { email: @hans.email, password: "secretsecret" }
  end

  test "GET /settings rendert den Einstellungs-Stack (#613)" do
    get "/settings"
    assert_response :success
    assert_includes response.body, 'data-uuid="list:settings"'
  end

  test "GET /settings ohne Login → Login-Page" do
    delete "/logout"
    get "/settings"
    assert_redirected_to login_path
  end
end
