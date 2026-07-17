require "test_helper"

# #1055 (aus #1051): Die Login-Brute-Force-Bremse war ungetestet, weil der
# Default-Cache im Test-Env ein Null-Store ist. Jetzt läuft sie über einen
# expliziten MemoryStore am Controller — hier scharf getestet.
class LoginRateLimitTest < ActionDispatch::IntegrationTest
  setup do
    SessionsController::RATE_LIMIT_STORE.clear
    @hans = create_human(password: "secretsecret")
    CapabilityDefaults.grant_full!(@hans)
  end

  teardown { SessionsController::RATE_LIMIT_STORE.clear }

  test "11. Fehlversuch wird gebremst (Redirect mit Alert statt Login-Versuch)" do
    10.times do
      post "/login", params: { email: @hans.email, password: "falsch" }
      assert_response :unauthorized
    end
    post "/login", params: { email: @hans.email, password: "falsch" }
    assert_redirected_to "/login"
    assert_equal I18n.t("sessions.rate_limited"), flash[:alert]
  end

  test "Bremse blockt auch korrekte Logins bis zum Fensterablauf, danach frei" do
    10.times { post "/login", params: { email: @hans.email, password: "falsch" } }
    post "/login", params: { email: @hans.email, password: "secretsecret" }
    assert_redirected_to "/login"
    assert_equal I18n.t("sessions.rate_limited"), flash[:alert]

    travel 4.minutes do
      post "/login", params: { email: @hans.email, password: "secretsecret" }
      assert_redirected_to "/dashboard"
    end
  end

  test "OTP-Schritt zählt in dasselbe Limit" do
    @hans.enable_otp!(ROTP::Base32.random)
    post "/login", params: { email: @hans.email, password: "secretsecret" }
    assert_redirected_to "/login/otp"

    10.times { post "/login/otp", params: { code: "000000" } }
    post "/login/otp", params: { code: "000000" }
    assert_redirected_to "/login"
    assert_equal I18n.t("sessions.rate_limited"), flash[:alert]
  end
end
