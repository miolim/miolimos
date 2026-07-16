require "test_helper"

# #1027: Compose-Ziel für „E-Mail schreiben" — auto löst über das
# verbundene Google-Konto auf, explizite Vorliebe gewinnt.
class ActorMailComposeTest < ActiveSupport::TestCase
  setup do
    @actor = HumanActor.create!(name: "Prefs", email: "prefs@test.local")
  end

  test "auto ohne Google-Konto = mailto" do
    assert_equal "mailto", @actor.pref_mail_compose_target
  end

  test "auto mit aktivem Google-Konto = gmail" do
    OauthCredential.create!(actor: @actor, provider: "google",
                            email_address: "prefs@example.com",
                            access_token: "x", refresh_token: "y",
                            expires_at: 1.hour.from_now,
                            scopes: ["scope1"], active: true)
    assert_equal "gmail", @actor.pref_mail_compose_target
  end

  test "inaktives Google-Konto zählt nicht" do
    OauthCredential.create!(actor: @actor, provider: "google",
                            email_address: "prefs@example.com",
                            access_token: "x", refresh_token: "y",
                            expires_at: 1.hour.from_now,
                            scopes: ["scope1"], active: false)
    assert_equal "mailto", @actor.pref_mail_compose_target
  end

  test "explizite Vorliebe gewinnt über auto" do
    @actor.update_preferences("mail_compose" => "gmail")
    assert_equal "gmail", @actor.reload.pref_mail_compose_target

    @actor.update_preferences("mail_compose" => "mailto")
    assert_equal "mailto", @actor.reload.pref_mail_compose_target
  end

  test "unbekannter Wert wird ignoriert" do
    @actor.update_preferences("mail_compose" => "pigeon")
    assert_nil @actor.reload.preferences["mail_compose"]
    assert_equal "mailto", @actor.pref_mail_compose_target
  end
end
