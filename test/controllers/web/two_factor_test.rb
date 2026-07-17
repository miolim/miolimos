require "test_helper"

# #1051: TOTP-Zweitfaktor — Enrollment (Settings → Sicherheit), zweistufiger
# Login, Recovery-Codes, Admin-Reset. Das Rails-rate_limit auf dem Login ist
# hier nicht testbar (test-Cache = :null_store) und bleibt Browser-Verify.
class TwoFactorTest < ActionDispatch::IntegrationTest
  setup do
    @hans = create_human(password: "secretsecret")
    CapabilityDefaults.grant_full!(@hans)
  end

  def login!
    post "/login", params: { email: @hans.email, password: "secretsecret" }
  end

  # ─── Enrollment ────────────────────────────────────────────────────────

  test "ohne 2FA bleibt der Login einstufig" do
    login!
    assert_redirected_to "/dashboard"
    get "/dashboard"
    assert_response :success
  end

  test "start → confirm mit gültigem Code aktiviert 2FA und zeigt Recovery-Codes einmalig" do
    login!
    post "/settings/two_factor/start"
    secret = session[:otp_setup_secret]
    assert secret.present?, "Kandidaten-Secret fehlt in der Session"
    assert_not @hans.reload.otp_enabled?, "start allein darf 2FA nicht aktivieren"

    post "/settings/two_factor/confirm", params: { code: ROTP::TOTP.new(secret).now }
    assert_redirected_to %r{/settings}
    follow_redirect!
    assert_response :success

    @hans.reload
    assert @hans.otp_enabled?
    assert_equal secret, @hans.otp_secret
    assert_equal HumanActor::OTP_RECOVERY_CODE_COUNT, @hans.otp_recovery_codes.size
    assert_nil session[:otp_setup_secret]
    # Einmalanzeige: Codes stehen im gerenderten Blade (aus dem Flash).
    assert_includes response.body, I18n.t("settings.two_factor.codes_heading")
  end

  test "confirm mit falschem Code aktiviert nichts" do
    login!
    post "/settings/two_factor/start"
    post "/settings/two_factor/confirm", params: { code: "000000" }
    assert_not @hans.reload.otp_enabled?
    assert session[:otp_setup_secret].present?, "Enrollment darf weiterlaufen"
  end

  # ─── Zweistufiger Login ────────────────────────────────────────────────

  test "mit 2FA: Passwort allein loggt nicht ein, gültiger TOTP-Code schon" do
    secret = ROTP::Base32.random
    @hans.enable_otp!(secret)

    login!
    assert_redirected_to "/login/otp"
    get "/dashboard"
    assert_redirected_to "/login"   # halb-authentifiziert = nicht drin

    post "/login/otp", params: { code: ROTP::TOTP.new(secret).now }
    assert_redirected_to "/dashboard"
    get "/dashboard"
    assert_response :success
  end

  test "falscher Code wird abgelehnt, derselbe Code kein zweites Mal akzeptiert" do
    secret = ROTP::Base32.random
    @hans.enable_otp!(secret)
    login!

    post "/login/otp", params: { code: "000000" }
    assert_response :unauthorized

    code = ROTP::TOTP.new(secret).now
    post "/login/otp", params: { code: code }
    assert_redirected_to "/dashboard"

    # Replay: ausloggen, erneut anmelden, denselben Code nochmal probieren.
    delete "/logout"
    login!
    post "/login/otp", params: { code: code }
    assert_response :unauthorized, "verbrauchter Timestep darf nicht nochmal gelten"
  end

  test "Recovery-Code loggt ein und ist danach verbraucht" do
    codes = @hans.enable_otp!(ROTP::Base32.random)
    login!
    post "/login/otp", params: { code: codes.first }
    assert_redirected_to "/dashboard"
    assert_equal codes.size - 1, @hans.reload.otp_recovery_codes.size

    delete "/logout"
    login!
    post "/login/otp", params: { code: codes.first }
    assert_response :unauthorized, "verbrauchter Recovery-Code darf nicht nochmal gelten"
  end

  test "abgelaufener Zwischenzustand führt zurück zum Login" do
    @hans.enable_otp!(ROTP::Base32.random)
    login!
    travel 6.minutes do
      get "/login/otp"
      assert_redirected_to "/login"
      post "/login/otp", params: { code: "000000" }
      assert_redirected_to "/login"
    end
  end

  # ─── Verwaltung ────────────────────────────────────────────────────────

  test "disable schaltet 2FA ab und räumt die Felder" do
    @hans.enable_otp!(ROTP::Base32.random)
    login!
    post "/login/otp", params: { code: ROTP::TOTP.new(@hans.otp_secret).now }

    post "/settings/two_factor/disable"
    @hans.reload
    assert_not @hans.otp_enabled?
    assert_nil @hans.otp_secret
    assert_empty @hans.otp_recovery_codes
  end

  test "Admin-Reset setzt die 2FA eines anderen Nutzers zurück" do
    other = create_human(name: "Karla", password: "secretsecret")
    other.enable_otp!(ROTP::Base32.random)

    login!
    post "/settings/users/#{other.id}/reset_two_factor"
    assert_not other.reload.otp_enabled?
  end

  test "Nicht-Admin darf fremde 2FA nicht zurücksetzen" do
    member = create_human(name: "Momo", role: :member, password: "secretsecret")
    CapabilityDefaults.grant_full!(member)
    other = create_human(name: "Karla", password: "secretsecret")
    other.enable_otp!(ROTP::Base32.random)

    post "/login", params: { email: member.email, password: "secretsecret" }
    post "/settings/users/#{other.id}/reset_two_factor"
    assert other.reload.otp_enabled?, "member darf fremde 2FA nicht zurücksetzen"
  end
end
