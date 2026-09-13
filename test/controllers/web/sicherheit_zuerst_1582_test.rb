require "test_helper"

# #1582 (Hans, aus immoOS #1581): „Auch bei miolim_os sollte man beständig auf
# 2FA hingewiesen werden, wenn es noch nicht eingerichtet ist."
#
# Anders als im Fork hängt der Start ohne neuen Login an `/` (StartController),
# nicht an /dashboard — /dashboard ist der Seitenleisten-Eintrag und bleibt
# ohne Umleitung, und die gewählte Startseite (#1582) kommt nach dem Hinweis.
class SicherheitZuerst1582Test < ActionDispatch::IntegrationTest
  SICHERHEIT = "/settings?stack=settings%3Asecurity".freeze

  setup do
    @hans = create_human(password: "secretsecret")
    CapabilityDefaults.grant_full!(@hans)
  end

  def login!
    post "/login", params: { email: @hans.email, password: "secretsecret" }
  end

  test "Login ohne 2FA führt zuerst auf die Sicherheits-Card" do
    login!
    assert_redirected_to SICHERHEIT
    follow_redirect!
    assert_response :success

    # Danach geht der Start ganz normal weiter — einmal je Sitzung.
    get "/"
    assert_redirected_to "/dashboard"
    get "/dashboard"
    assert_response :success
  end

  test "mit 2FA bleibt es bei der Startseite" do
    @hans.enable_otp!(ROTP::Base32.random)
    login!
    post "/login/otp", params: { code: ROTP::TOTP.new(@hans.reload.otp_secret).now }
    assert_redirected_to "/dashboard"

    get "/"
    assert_redirected_to "/dashboard"
  end

  test "ein echter Deep-Link gewinnt, die Sicherheits-Card kommt beim nächsten Start" do
    get "/tasks"
    assert_redirected_to "/login"
    login!
    assert_redirected_to "/tasks"

    get "/"
    assert_redirected_to SICHERHEIT, "beim Start ohne 2FA kommt sie jetzt"
    get "/"
    assert_redirected_to "/dashboard", "und nur einmal je Sitzung"
  end

  test "die Startseite als Rücksprungziel ist kein Deep-Link" do
    get "/"
    login!
    assert_redirected_to SICHERHEIT
  end

  test "der Dashboard-Eintrag der Seitenleiste wird nicht umgeleitet" do
    get "/tasks"
    login!
    get "/dashboard"
    assert_response :success
  end

  test "nach dem Hinweis kommt die gewählte Startseite" do
    @hans.update_preferences("start_stack" => "tasks")
    get "/tasks"
    login!

    get "/"
    assert_redirected_to SICHERHEIT
    get "/"
    assert_redirected_to "/tasks"
  end

  test "ohne Recht auf die Einstellungsseite keine Umleitung ins Leere" do
    Capability.where(actor: @hans, resource_type: "Actor").delete_all
    login!
    assert_redirected_to "/dashboard"
    get "/"
    assert_redirected_to "/dashboard"
  end
end
