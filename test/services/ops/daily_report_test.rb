require "test_helper"

# #1076. Die Faelle sind nicht erfunden — jeder von ihnen ist am 21.07.2026
# tatsaechlich eingetreten und blieb unbemerkt. Der Bericht existiert, damit
# genau diese Zeilen kuenftig auf Hans' Bildschirm landen.
module Ops
  class DailyReportTest < ActiveSupport::TestCase
    setup do
      @dir = Dir.mktmpdir
      @now = Time.zone.parse("2026-07-21 09:00:00")
      # Ausgangslage: Mailversand in Ordnung. Sonst schlaegt der
      # Postausgang-Abschnitt in jedem Test an und verfaelscht die
      # Alarm-Zaehlung. Die Postausgang-Tests setzen ihn selbst neu.
      healthy_credential
    end

    def healthy_credential
      OauthCredential.where(provider: "google").delete_all
      OauthCredential.create!(actor: create_human, provider: "google",
                              email_address: "postausgang-ok@test.local",
                              active: true, expires_at: @now + 30.days)
    end

    teardown { FileUtils.remove_entry(@dir) }

    def write(name, content)
      path = File.join(@dir, name)
      File.write(path, content)
      path
    end

    def report(state: nil, events: nil, backup: nil, repos: {}, probe: nil)
      DailyReport.new(
        state_file: state || File.join(@dir, "fehlt-state"),
        event_log:  events || File.join(@dir, "fehlt-events"),
        backup_log: backup || File.join(@dir, "fehlt-backup"),
        repos:      repos,
        repo_probe: probe || ->(_path) { { status: :synced } },
        now:        @now
      )
    end

    def section(report, title)
      report.sections.find { |s| s.title == title }.lines.join("\n")
    end

    def healthy_backup
      write("backup.log", <<~LOG)
        [2026-07-21 04:30:01] backup start
        [2026-07-21 04:30:06] ok miolimos_production (11614586 bytes)
        [2026-07-21 04:30:08] ok monica_production (339799 bytes)
        [2026-07-21 04:30:44] backup done (errors=0)
      LOG
    end

    # ── Dienste ───────────────────────────────────────────────────────────

    test "laufende Dienste erzeugen keinen Alarm" do
      state = write("state", "miolimos up 1753080000\nstocker up 1753080000\n")
      r = report(state: state, backup: healthy_backup)
      assert_empty r.alerts
      assert_includes r.sections.first.lines.join("\n"), "miolimos: laeuft"
      assert_match(/alles gruen/, r.subject)
    end

    test "ein ausgefallener Dienst wird zum Alarm mit letztem Erfolgszeitpunkt" do
      last_ok = Time.zone.parse("2026-07-21 07:34:00").to_i
      state = write("state", "stocker down #{last_ok}\n")
      r = report(state: state, backup: healthy_backup)
      assert_equal 1, r.alerts.size
      assert_match(/stocker antwortet nicht/, r.alerts.first)
      assert_match(/21\.07\. 07:34/, r.alerts.first)
      assert_match(/1 Auffaelligkeit/, r.subject)
    end

    test "ein nie erreichbarer Dienst ist sichtbar, aber kein Alarm" do
      state = write("state", "neueinstanz unseen 0\n")
      r = report(state: state, backup: healthy_backup)
      assert_empty r.alerts
      assert_includes r.sections.first.lines.join("\n"), "noch nie erreichbar gesehen"
    end

    test "fehlende Zustandsdatei meldet den Waechter selbst als auffaellig" do
      r = report(backup: healthy_backup)
      assert(r.alerts.any? { |a| a.include?("Waechter hat noch nie gelaufen") })
    end

    test "Ereignisse der letzten 24 Stunden stehen im Bericht, aeltere nicht" do
      state  = write("state", "miolimos up 1753080000\n")
      events = write("events.log", <<~LOG)
        [2026-07-18 03:00:00] DOWN uralt (Port 1) — zuletzt erreichbar 2026-07-18 02:00:00
        [2026-07-21 07:34:12] DOWN stocker (Port 3106) — zuletzt erreichbar 2026-07-21 07:33:00
        [2026-07-21 08:15:00] RECOVERED stocker (Port 3106) — war 2508s nicht erreichbar
      LOG
      lines = report(state: state, events: events, backup: healthy_backup).sections.first.lines.join("\n")
      assert_includes lines, "DOWN stocker"
      assert_includes lines, "RECOVERED stocker"
      refute_includes lines, "uralt"
    end

    # ── Datensicherung ────────────────────────────────────────────────────

    test "erfolgreiche Sicherung wird ohne Alarm berichtet" do
      r = report(backup: healthy_backup, state: write("state", "miolimos up 1\n"))
      backup = r.sections.find { |s| s.title == "Datensicherung" }
      assert_includes backup.lines.join("\n"), "fehlerfrei"
      assert_empty r.alerts
    end

    test "eine verschwundene Datenbank aus dem Backup wird nach oben gezogen" do
      # Genau der Fall aus #1064 Nachtrag 2: die umbenannte Produktiv-DB.
      log = write("backup.log", <<~LOG)
        [2026-07-21 04:30:01] backup start
        [2026-07-21 04:30:06] ok miolimos_production (11614586 bytes)
        [2026-07-21 04:30:07] MISSING miolimmo_production (war frueher gesichert, zuletzt miolimmo_production-20260720-043001.dump) — umbenannt oder geloescht?
        [2026-07-21 04:30:44] backup done (errors=1)
      LOG
      r = report(backup: log, state: write("state", "miolimos up 1\n"))
      assert(r.alerts.any? { |a| a.include?("MISSING miolimmo_production") })
      assert(r.alerts.any? { |a| a.include?("meldet Fehler") })
    end

    test "eine veraltete Sicherung faellt auf" do
      log = write("backup.log", "[2026-07-18 04:30:44] backup done (errors=0)\n")
      r = report(backup: log, state: write("state", "miolimos up 1\n"))
      assert(r.alerts.any? { |a| a.include?("letzte Datensicherung ist") })
    end

    test "fehlendes Backup-Protokoll ist ein Alarm" do
      r = report(state: write("state", "miolimos up 1\n"))
      assert(r.alerts.any? { |a| a.include?("Kein Backup-Protokoll") })
    end


    # ── Postausgang ───────────────────────────────────────────────────────
    # Der Bericht prueft seinen eigenen Zustellweg. Am 21.07.2026 war die
    # Google-Credential zehn Tage abgelaufen, und niemand hat es bemerkt.

    test "eine abgelaufene Mail-Credential ist ein Alarm mit Handlungsanweisung" do
      OauthCredential.where(provider: "google").delete_all
      OauthCredential.create!(actor: create_human, provider: "google",
                              email_address: "test-abgelaufen@example.com",
                              active: false, expires_at: Time.zone.parse("2026-07-11 11:30"))
      r = report(state: write("state", "miolimos up 1\n"), backup: healthy_backup)
      assert(r.alerts.any? { |a| a.include?("Mailversand ist abgeschaltet") })
      assert(r.alerts.any? { |a| a.include?("11.07.2026") })
      assert(r.alerts.any? { |a| a.include?("Einstellungen") }, "muss sagen, was zu tun ist")
    end

    test "eine bald ablaufende Credential warnt VOR dem Ablauf" do
      OauthCredential.where(provider: "google").delete_all
      OauthCredential.create!(actor: create_human, provider: "google",
                              email_address: "test-bald@example.com",
                              active: true, expires_at: @now + 2.days)
      r = report(state: write("state", "miolimos up 1\n"), backup: healthy_backup)
      assert(r.alerts.any? { |a| a.include?("laeuft am") })
    end

    test "eine gesunde Credential erzeugt keinen Alarm" do
      OauthCredential.where(provider: "google").delete_all
      OauthCredential.create!(actor: create_human, provider: "google",
                              email_address: "test-ok@example.com",
                              active: true, expires_at: @now + 30.days)
      r = report(state: write("state", "miolimos up 1\n"), backup: healthy_backup)
      assert_empty r.alerts
      assert_includes r.sections.map(&:title), "Postausgang"
    end

    test "gar kein verbundenes Konto ist ein Alarm" do
      OauthCredential.where(provider: "google").delete_all
      r = report(state: write("state", "miolimos up 1\n"), backup: healthy_backup)
      assert(r.alerts.any? { |a| a.include?("kein Google-Konto verbunden") })
    end

    # ── Code-Sicherung ────────────────────────────────────────────────────

    test "unveroeffentlichte Arbeit wird gemeldet, mit Alter des aeltesten Commits" do
      # Der Fall, der vier Wochen unbemerkt blieb.
      probe = ->(_p) { { status: :ahead, ahead: 202,
                         oldest_unpushed: Time.zone.parse("2026-06-21 15:22:00") } }
      r = report(state: write("state", "miolimos up 1\n"), backup: healthy_backup,
                 repos: { "App-Code" => "/irgendwo" }, probe: probe)
      assert(r.alerts.any? { |a| a.include?("202 Commits liegen nur auf dieser Maschine") })
      assert(r.alerts.any? { |a| a.include?("21.06.2026 15:22") }, "Alter muss genannt sein")
    end

    test "frisch committete Arbeit ist noch kein Alarm" do
      # Der stuendliche Push darf seine Runde noch fahren duerfen.
      probe = ->(_p) { { status: :ahead, ahead: 1, oldest_unpushed: @now - 10.minutes } }
      r = report(state: write("state", "miolimos up 1\n"), backup: healthy_backup,
                 repos: { "App-Code" => "/irgendwo" }, probe: probe)
      assert_empty r.alerts
      assert_includes section(r, "Code-Sicherung nach GitHub"), "warten auf den naechsten Push"
    end

    test "ein vollstaendig gepushtes Repo erzeugt keinen Alarm" do
      r = report(state: write("state", "miolimos up 1\n"), backup: healthy_backup,
                 repos: { "Wissensdateien" => "/irgendwo" })
      assert_empty r.alerts
      assert_includes section(r, "Code-Sicherung nach GitHub"), "vollstaendig auf GitHub"
    end

    test "ein Repo ganz ohne Fernkopie ist ein Alarm" do
      probe = ->(_p) { { status: :no_remote } }
      r = report(state: write("state", "miolimos up 1\n"), backup: healthy_backup,
                 repos: { "Datenverzeichnis" => "/irgendwo" }, probe: probe)
      assert(r.alerts.any? { |a| a.include?("keine Fernkopie") })
    end


    # Die vorigen Faelle stecken die Repo-Pruefung als Attrappe hinein. Hier
    # laeuft sie einmal echt — gegen ein wegwerfbares Repo mit Fernkopie,
    # damit auch die git-Aufrufe selbst abgesichert sind.
    test "die echte Repo-Pruefung erkennt gepusht, unveroeffentlicht und remote-los" do
      skip "git nicht verfuegbar" unless system("git --version > /dev/null 2>&1")

      remote = File.join(@dir, "remote.git")
      work   = File.join(@dir, "work")
      sh = ->(*args) { system(*args, out: File::NULL, err: File::NULL) || flunk("Kommando fehlgeschlagen: #{args.join(' ')}") }

      sh.call("git", "init", "--bare", "-q", remote)
      sh.call("git", "init", "-q", work)
      sh.call("git", "-C", work, "config", "user.email", "test@example.com")
      sh.call("git", "-C", work, "config", "user.name", "Test")
      File.write(File.join(work, "a.txt"), "eins")
      sh.call("git", "-C", work, "add", "-A")
      sh.call("git", "-C", work, "commit", "-q", "-m", "erster")

      probe = Ops::DailyReport.new.send(:method, :git_state)

      # 1. ohne Fernkopie
      assert_equal :no_remote, probe.call(work)[:status]

      # 2. nach dem Push: synchron
      sh.call("git", "-C", work, "remote", "add", "origin", remote)
      sh.call("git", "-C", work, "push", "-q", "-u", "origin", "HEAD")
      assert_equal :synced, probe.call(work)[:status]

      # 3. ein neuer Commit liegt nur lokal
      File.write(File.join(work, "b.txt"), "zwei")
      sh.call("git", "-C", work, "add", "-A")
      sh.call("git", "-C", work, "commit", "-q", "-m", "zweiter")
      state = probe.call(work)
      assert_equal :ahead, state[:status]
      assert_equal 1, state[:ahead]
      assert_kind_of ActiveSupport::TimeWithZone, state[:oldest_unpushed]

      # 4. gar kein Repository
      assert_equal :missing, probe.call(File.join(@dir, "nichts"))[:status]
    end

    test "der Bericht ueberlebt fehlende Protokolldateien ohne Absturz" do
      probe = ->(_p) { { status: :missing } }
      r = report(repos: { "App-Code" => File.join(@dir, "gibtsnicht") }, probe: probe)
      assert_nothing_raised { r.subject }
      assert_includes section(r, "Code-Sicherung nach GitHub"), "kein Repository unter"
    end
  end
end
