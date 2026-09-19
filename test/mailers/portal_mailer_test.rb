require "test_helper"

# #1675: Die Portal-Mails wurden bisher nirgends GERENDERT — die Flow-Tests
# prüfen nur, dass eine Mail eingereiht wird (assert_enqueued_emails). Ein
# kaputtes Template, ein fehlender i18n-Schlüssel oder ein umbenannter
# URL-Helfer ließe den MailDeliveryJob im Hintergrund scheitern, während das
# Portal dem Kunden weiter „Link ist unterwegs" zeigt. Der Kunde kommt dann
# nie hinein, und bei uns fällt es nicht auf.
class PortalMailerTest < ActionMailer::TestCase
  setup do
    @hans = create_human
    OauthCredential.where(provider: "google").delete_all
    OauthCredential.create!(actor: @hans, provider: "google",
                            email_address: "absender@test.local",
                            active: true, expires_at: 30.days.from_now,
                            refresh_token: "vorhanden")
    @projekt = Topic.create!(name: "Projekt Alpha", slug: "pa-#{SecureRandom.hex(3)}", creator: @hans)
    @access  = PortalAccess.create!(topic: @projekt, email: "kunde@example.com")
  end

  def html_von(mail)
    (mail.html_part || mail).body.decoded
  end

  test "magic_link: Link traegt ein gueltiges Token und zeigt auf den Portal-Host" do
    mail = PortalMailer.magic_link(@access)

    assert_equal ["kunde@example.com"], mail.to
    assert_includes mail.subject, "Projekt Alpha"

    url = html_von(mail)[%r{https?://[^"'<\s]+}]
    assert url, "keine URL im Mail-Body"
    uri = URI.parse(CGI.unescapeHTML(url))
    assert_equal PortalMailer.portal_host, uri.host

    # Das Token aus der Mail muss den Zugang wirklich öffnen — sonst ist der
    # Link hübsch, aber tot.
    token = CGI.unescape(uri.path.split("/").last)
    assert_equal @access, PortalAccess.from_magic_token(token)

    # … und der Pfad muss auf die Anmelde-Route des Portals treffen.
    assert_equal "consume", Rails.application.routes.recognize_path(uri.path)[:action]
  end

  test "magic_link rendert in jeder Portal-Sprache ohne fehlende Uebersetzung" do
    PortalAccess::LOCALES.each do |locale|
      @access.update!(locale: locale)
      mail = PortalMailer.magic_link(@access)
      refute_match(/translation missing/i, mail.subject, "Betreff (#{locale})")
      refute_match(/translation[ _]missing/i, html_von(mail), "Body (#{locale})")
    end
  end

  test "update_ping nennt den Anlass und verlinkt das Portal, in jeder Sprache" do
    PortalAccess::LOCALES.each do |locale|
      @access.update!(locale: locale)
      mail = PortalMailer.update_ping(@access, what: "Neue Freigabe: Angebot.pdf")
      body = html_von(mail)
      assert_equal ["kunde@example.com"], mail.to
      assert_includes body, "Neue Freigabe: Angebot.pdf"
      assert_includes body, PortalMailer.portal_host
      refute_match(/translation[ _]missing/i, mail.subject + body, "(#{locale})")
    end
  end

  test "customer_message_internal geht ans eigene Postfach und zitiert die Nachricht" do
    nachricht = Struct.new(:body).new("Wann kommt der Entwurf?")
    mail = PortalMailer.customer_message_internal(nachricht, @access)

    assert_equal ["absender@test.local"], mail.to
    assert_includes mail.subject, "kunde@example.com"
    assert_includes html_von(mail), "Wann kommt der Entwurf?"
  end

  test "customer_message_internal ohne verbundenes Konto verschickt nichts, statt zu scheitern" do
    OauthCredential.where(provider: "google").delete_all

    assert_no_emails do
      PortalMailer.customer_message_internal(Struct.new(:body).new("Hallo"), @access).deliver_now
    end
  end
end
