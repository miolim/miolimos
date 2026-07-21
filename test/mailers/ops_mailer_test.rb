require "test_helper"

# #1076: der taegliche Betriebsbericht.
class OpsMailerTest < ActionMailer::TestCase
  setup do
    # Ausgangslage: Mailversand in Ordnung — sonst meldet der
    # Postausgang-Abschnitt eine Auffaelligkeit und der "gruene" Fall
    # existiert gar nicht.
    OauthCredential.where(provider: "google").delete_all
    OauthCredential.create!(actor: create_human, provider: "google",
                            email_address: "postausgang-ok@test.local",
                            active: true, expires_at: 30.days.from_now)
  end

  def report_with(alerts:)
    log = Tempfile.new("backup")
    log.write(alerts ? "[2026-07-21 04:30:44] backup done (errors=1)\n"
                     : "[2026-07-21 04:30:44] backup done (errors=0)\n")
    log.flush
    state = Tempfile.new("state")
    state.write("miolimos up #{Time.zone.parse('2026-07-21 08:00').to_i}\n")
    state.flush
    # Schluessel und Zustandsdatei ausdruecklich setzen: config/master.key ist
    # gitignoriert und existiert in einem frischen Checkout (CI!) nicht — ein
    # Test, der ihn stillschweigend erwartet, ist genau die Umgebungs-
    # abhaengigkeit, die #1076 beim Host beseitigt hat.
    key = Tempfile.new("masterkey")
    key.write("x" * 32)
    key.flush
    keystate = Tempfile.new("keystate")
    @tempfiles = [ log, state, key, keystate ]
    Ops::DailyReport.new(state_file: state.path, event_log: "/nonexistent",
                         backup_log: log.path, repos: {},
                         key_files: { "Master-Key" => key.path },
                         key_state_file: keystate.path,
                         # Auch die Datenbank-Abfrage ausdruecklich setzen: der
                         # Vorgabewert fragt die echte Maschine, und dann haengt
                         # der "gruene" Fall daran, welche DBs zufaellig
                         # existieren. Dritter Anlauf derselben Lektion.
                         database_probe: -> { [] },
                         now: Time.zone.parse("2026-07-21 09:00"))
  end

  teardown { Array(@tempfiles).each(&:close!) }

  test "gruener Bericht nennt das im Betreff und geht an den Empfaenger" do
    mail = OpsMailer.daily_report(report_with(alerts: false), to: "hans@example.com")
    assert_equal [ "hans@example.com" ], mail.to
    assert_match(/alles gruen/, mail.subject)
    assert_match(/unauffällig/, mail.body.encoded)
  end

  test "Auffaelligkeiten stehen im Betreff und oben im Text" do
    mail = OpsMailer.daily_report(report_with(alerts: true), to: "hans@example.com")
    assert_match(/Auffaelligkeit/, mail.subject)
    assert_match(/MIT FEHLERN/, mail.body.encoded)
  end

  test "der Absender bleibt leer, damit GmailSender ihn setzt" do
    mail = OpsMailer.daily_report(report_with(alerts: false), to: "hans@example.com")
    assert mail.from.blank? || mail.from == [ "from@example.com" ],
      "OpsMailer darf keinen eigenen Absender erzwingen"
  end
end
