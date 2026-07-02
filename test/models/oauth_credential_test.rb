require "test_helper"

class OauthCredentialTest < ActiveSupport::TestCase
  def build_cred(**overrides)
    OauthCredential.new({
      actor:         create_human,
      provider:      "google",
      email_address: "#{SecureRandom.hex(4)}@example.com",
      access_token:  "access-#{SecureRandom.hex(4)}",
      refresh_token: "refresh-#{SecureRandom.hex(4)}",
      expires_at:    1.hour.from_now,
      scopes:        ["https://www.googleapis.com/auth/gmail.readonly"],
      active:        true
    }.merge(overrides))
  end

  test "requires provider and email" do
    c = OauthCredential.new(actor: create_human)
    refute_predicate c, :valid?
    assert c.errors.added?(:email_address, :blank)
  end

  test "email is unique" do
    c1 = build_cred(email_address: "dup@example.com")
    c1.save!
    c2 = build_cred(email_address: "dup@example.com")
    refute_predicate c2, :valid?
  end

  test "access_token and refresh_token are encrypted at rest" do
    c = build_cred(access_token: "plain-access-token", refresh_token: "plain-refresh-token")
    c.save!

    row = OauthCredential.connection.select_one(
      "SELECT access_token_ciphertext, refresh_token_ciphertext FROM oauth_credentials WHERE id=#{c.id}"
    )
    refute_equal "plain-access-token", row["access_token_ciphertext"]
    refute_equal "plain-refresh-token", row["refresh_token_ciphertext"]

    reloaded = OauthCredential.find(c.id)
    assert_equal "plain-access-token", reloaded.access_token
    assert_equal "plain-refresh-token", reloaded.refresh_token
  end

  test "active scope" do
    a = build_cred.tap(&:save!)
    b = build_cred(active: false).tap(&:save!)
    assert_includes OauthCredential.active, a
    refute_includes OauthCredential.active, b
  end

  test "for_email scope" do
    c = build_cred(email_address: "unique@acme.io").tap(&:save!)
    assert_equal [c], OauthCredential.for_email("unique@acme.io").to_a
  end

  test "expired? returns true within buffer window" do
    c = build_cred(expires_at: 30.seconds.from_now)
    assert_predicate c, :expired?

    c.expires_at = 10.minutes.from_now
    refute_predicate c, :expired?
  end
end
