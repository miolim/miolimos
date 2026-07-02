require "test_helper"

# #203: Coverage fuer den Gmail-OAuth-Settings-Tab. OAuth-Flow (connect/
# callback) wird nicht End-to-End getestet (braucht Google-Stub),
# stattdessen Index, Destroy und Fehler-Pfade.
class SettingsAccountsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @hans = HumanActor.create!(name: "Hans",
                                email: "hans-sa-#{SecureRandom.hex(3)}@t.local",
                                password: "secretsecret")
    grant(@hans, "OauthCredential", %w[read create update delete])
    grant(@hans, "Actor", %w[read])   # #613: Settings-Stack-Gate
    post "/login", params: { email: @hans.email, password: "secretsecret" }
  end

  test "GET /settings/accounts listet Credentials" do
    OauthCredential.create!(actor: @hans, provider: "google",
                             email_address: "test@example.com",
                             access_token: "x", refresh_token: "y",
                             expires_at: 1.hour.from_now,
                             scopes: ["scope1"], active: true)
    get "/settings/accounts"
    follow_redirect!   # #613
    assert_response :success
    assert_includes @response.body, "test@example.com"
  end

  test "DELETE /settings/accounts/:id entfernt das Credential" do
    cred = OauthCredential.create!(actor: @hans, provider: "google",
                                    email_address: "drop@example.com",
                                    access_token: "x", refresh_token: "y",
                                    expires_at: 1.hour.from_now,
                                    scopes: ["scope1"], active: true)
    assert_difference -> { OauthCredential.count }, -1 do
      delete "/settings/accounts/#{cred.id}"
    end
    assert_redirected_to settings_accounts_path
    assert_match(/getrennt/, flash[:notice].to_s)
    follow_redirect!   # → /settings/accounts (Legacy-Redirect, #613)
    follow_redirect!   # → /settings?stack=…,settings:accounts
    assert_includes @response.body, "drop@example.com"
  end

  test "GET callback ohne State-Cookie liefert State-Mismatch" do
    get "/settings/accounts/callback", params: { code: "abc", state: "anything" }
    assert_redirected_to settings_accounts_path
    follow_redirect!
    assert_match(/State-Mismatch/, flash[:alert].to_s)
  end

  test "GET callback mit error-Param liefert Google-Fehler-Flash" do
    get "/settings/accounts/callback", params: { error: "access_denied" }
    assert_redirected_to settings_accounts_path
    follow_redirect!
    assert_match(/Google-Fehler.*access_denied/, flash[:alert].to_s)
  end

  test "GET connect ohne vollständige Client-Konfig erklärt statt 500" do
    # #536: fehlendes oauth_client_secret (oder client_id) → Redirect mit
    # verständlicher Meldung inkl. Fundort, kein 500 mehr (Hans-Report).
    # Credentials stubben — auf der Box sind sie inzwischen vollständig.
    ENV.delete("GOOGLE_OAUTH_CLIENT_ID")
    ENV.delete("GOOGLE_OAUTH_CLIENT_SECRET")
    leer = ActiveSupport::OrderedOptions.new
    app  = Rails.application
    app.define_singleton_method(:credentials) { leer }
    begin
      get "/settings/accounts/connect"
    ensure
      app.singleton_class.remove_method(:credentials)
    end
    assert_redirected_to settings_accounts_path
    assert_match(/oauth_client_(secret|id)/, flash[:alert].to_s)
    assert_match(/credentials:edit/, flash[:alert].to_s)
  end

  test "Ohne Capability sieht User 403" do
    delete "/logout"
    no_caps = HumanActor.create!(name: "NC", email: "nc-#{SecureRandom.hex(2)}@t.local",
                                  password: "secretsecret")
    post "/login", params: { email: no_caps.email, password: "secretsecret" }
    get "/settings/accounts"
    assert_response :forbidden
  end
  # #573-Folge: Ziel-Kalender pro Konto pflegbar (leer = primary).
  test "PATCH update_settings setzt und leert die GCal-Kalender-ID" do
    cred = OauthCredential.create!(actor: @hans, provider: "google",
                                   email_address: "cal-#{SecureRandom.hex(3)}@test.local")
    patch "/settings/accounts/#{cred.id}/update_settings",
          params: { gcal_calendar_id: "kunde@group.calendar.google.com" }
    assert_redirected_to settings_accounts_path
    assert_equal "kunde@group.calendar.google.com", cred.reload.gcal_calendar_id

    patch "/settings/accounts/#{cred.id}/update_settings", params: { gcal_calendar_id: "  " }
    assert_nil cred.reload.gcal_calendar_id
  end
end
