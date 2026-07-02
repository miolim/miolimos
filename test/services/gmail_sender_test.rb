require "test_helper"

# #801 P1: Tests für den Gmail-Versandweg (#536) — der einzige Weg, auf dem
# die App Mail verschickt (Portal!). Gmail-API wird gestubbt, geprüft wird
# die Logik drumherum: Scope-Gate, From-Default, Fehlerübersetzung, Retry.
class GmailSenderTest < ActiveSupport::TestCase
  SEND_SCOPE = GmailSender::SEND_SCOPE

  setup do
    @hans = create_human
  end

  def create_credential(scopes: [SEND_SCOPE], **attrs)
    OauthCredential.create!({
      actor: @hans, provider: "google",
      email_address: "sender@example.com",
      access_token: "at", refresh_token: "rt",
      expires_at: 1.hour.from_now,
      active: true, scopes: scopes
    }.merge(attrs))
  end

  def build_mail(from: nil)
    Mail.new do
      to      "empfaenger@example.com"
      subject "Betreff"
      body    "Hallo"
    end.tap { |m| m.from = from if from }
  end

  # Ersetzt das private #service durch einen Fake und schaltet den echten
  # Token-Refresh ab (kein Netz im Test).
  def stub_service(sender, fake)
    sender.define_singleton_method(:service) { fake }
    sender.define_singleton_method(:refresh_token_if_needed!) { nil }
    sender
  end

  class FakeGmailService
    attr_reader :sent
    def initialize(fail_first_with: nil)
      @sent = []
      @fail_first_with = fail_first_with
    end

    def send_user_message(user, msg)
      if @fail_first_with
        err, @fail_first_with = @fail_first_with, nil
        raise err
      end
      @sent << [user, msg]
      Struct.new(:id).new("gmail-msg-#{@sent.size}")
    end
  end

  test "available? and send_scope_granted? reflect the stored credential" do
    assert_not GmailSender.available?
    assert_not GmailSender.send_scope_granted?

    create_credential(scopes: ["other.scope"])
    assert GmailSender.available?
    assert_not GmailSender.send_scope_granted?

    OauthCredential.delete_all
    create_credential
    assert GmailSender.send_scope_granted?
  end

  test "initialize without credential raises a clear error" do
    assert_raises(GmailSender::Error) { GmailSender.new(nil) }
  end

  test "deliver! without send scope raises before any API call" do
    cred   = create_credential(scopes: ["only.readonly"])
    sender = GmailSender.new(cred)
    err = assert_raises(GmailSender::Error) { sender.deliver!(build_mail) }
    assert_match(/Send-Scope fehlt/, err.message)
  end

  test "deliver! sends raw message and returns the Gmail message id" do
    fake   = FakeGmailService.new
    sender = stub_service(GmailSender.new(create_credential), fake)

    id = sender.deliver!(build_mail(from: "explizit@example.com"))
    assert_equal "gmail-msg-1", id

    user, msg = fake.sent.first
    assert_equal "me", user
    assert_includes msg.raw, "To: empfaenger@example.com"
    assert_includes msg.raw, "From: explizit@example.com"
  end

  test "deliver! defaults From to the credential mailbox" do
    fake   = FakeGmailService.new
    sender = stub_service(GmailSender.new(create_credential), fake)

    sender.deliver!(build_mail)
    _, msg = fake.sent.first
    assert_includes msg.raw, "From: sender@example.com"
  end

  test "deliver! retries once after an authorization error" do
    fake   = FakeGmailService.new(fail_first_with: Signet::AuthorizationError.new("expired"))
    sender = stub_service(GmailSender.new(create_credential), fake)

    assert_equal "gmail-msg-1", sender.deliver!(build_mail)
    assert_equal 1, fake.sent.size
  end

  test "deliver! wraps persistent API errors in GmailSender::Error" do
    fake   = FakeGmailService.new(fail_first_with: Google::Apis::ClientError.new("bad request"))
    sender = stub_service(GmailSender.new(create_credential), fake)

    err = assert_raises(GmailSender::Error) { sender.deliver!(build_mail) }
    assert_match(/Gmail-Versand fehlgeschlagen/, err.message)
  end
end
