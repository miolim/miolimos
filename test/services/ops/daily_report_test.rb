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
      @key_path = File.join(@dir, "master.key")
      File.write(@key_path, "0" * 32)
    end

    def healthy_credential
      OauthCredential.where(provider: "google").delete_all
      OauthCredential.create!(actor: create_human, provider: "google",
                              email_address: "postausgang-ok@test.local",
                              active: true, expires_at: @now + 30.days,
                              refresh_token: "vorhanden")
    end

    teardown { FileUtils.remove_entry(@dir) }

    def write(name, content)
      path = File.join(@dir, name)
      File.write(path, content)
      path
    end

    # EIN Satz neutraler Argumente fuer ALLE Konstruktionen im Test.
    #
    # Grund: DailyReport hat lauter Vorgabewerte, die die ECHTE Maschine lesen
    # (Zustandsdatei des Waechters, Backup-Protokoll, config/master.key, die
    # Registry, die Datenbankliste). Ein Test, der nur die halbe Liste
    # ueberschreibt, haengt still am Rechner, auf dem er zufaellig laeuft —
    # das ist mir am 21.07. VIERMAL passiert, zuletzt durch einen neu
    # hinzugekommenen Parameter, der zwei bestehende Tests umwarf.
    # Kommt kuenftig ein Vorgabewert dazu, gehoert er hier hinein, und zwar
    # genau einmal.
    def neutrale_args(**ueber)
      {
        state_file:     File.join(@dir, "fehlt-state"),
        event_log:      File.join(@dir, "fehlt-events"),
        backup_log:     File.join(@dir, "fehlt-backup"),
        repos:          {},
        repo_probe:     ->(_path) { { status: :synced } },
        key_files:      { "Master-Key" => @key_path },
        key_state_file: File.join(@dir, "keystate"),
        database_probe: -> { [] },
        registry_file:  File.join(@dir, "keine-registry"),
        now:            @now
      }.merge(ueber)
    end

    def report(state: nil, events: nil, backup: nil, repos: {}, probe: nil, keys: nil,
               dbs: nil, ignoriert: [], registry: nil, key_state: nil)
      args = neutrale_args(repos: repos, ignored_databases: ignoriert)
      args[:state_file]     = state    if state
      args[:event_log]      = events   if events
      args[:backup_log]     = backup   if backup
      args[:repo_probe]     = probe    if probe
      args[:key_files]      = keys     if keys
      args[:database_probe] = dbs      if dbs
      args[:registry_file]  = registry if registry
      # #1220: eigene Zustandsdatei — fuer den Mehr-Instanzen-Fall.
      args[:key_state_file] = key_state if key_state
      DailyReport.new(**args)
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

    test "ein bald ablaufendes Zugriffstoken ist KEIN Alarm" do
      # Es erneuert sich selbst (GmailSender#refresh_token_if_needed!). Eine
      # Warnung darauf haette jeden Tag gefeuert, an dem alles in Ordnung ist —
      # und taeglicher Alarm ohne Anlass bringt ein Ueberwachungssystem um.
      OauthCredential.where(provider: "google").delete_all
      OauthCredential.create!(actor: create_human, provider: "google",
                              email_address: "test-bald@example.com",
                              active: true, expires_at: @now + 30.minutes,
                              refresh_token: "vorhanden")
      r = report(state: write("state", "miolimos up 1\n"), backup: healthy_backup)
      assert_empty r.alerts
      assert_includes section(r, "Postausgang"), "erneuert sich selbst"
    end

    test "eine Credential ohne Erneuerungs-Token ist ein Alarm" do
      OauthCredential.where(provider: "google").delete_all
      OauthCredential.create!(actor: create_human, provider: "google",
                              email_address: "test-ohne@example.com",
                              active: true, expires_at: @now + 30.minutes,
                              refresh_token: nil)
      r = report(state: write("state", "miolimos up 1\n"), backup: healthy_backup)
      assert(r.alerts.any? { |a| a.include?("Erneuerungs-Token") && a.include?("Neu verbinden") })
      assert_includes section(r, "Postausgang"), "kein Erneuerungs-Token"
    end

    test "eine gesunde Credential erzeugt keinen Alarm" do
      OauthCredential.where(provider: "google").delete_all
      OauthCredential.create!(actor: create_human, provider: "google",
                              email_address: "test-ok@example.com",
                              active: true, expires_at: @now + 30.days,
                              refresh_token: "vorhanden")
      r = report(state: write("state", "miolimos up 1\n"), backup: healthy_backup)
      assert_empty r.alerts
      assert_includes r.sections.map(&:title), "Postausgang"
    end

    test "gar kein verbundenes Konto ist ein Alarm" do
      OauthCredential.where(provider: "google").delete_all
      r = report(state: write("state", "miolimos up 1\n"), backup: healthy_backup)
      assert(r.alerts.any? { |a| a.include?("kein Google-Konto verbunden") })
    end


    # ── Schluessel ────────────────────────────────────────────────────────
    # config/master.key liegt bewusst nicht im Backup; seine einzige
    # Zweitschrift ist der Passwortmanager. Ein Wechsel macht die still
    # wertlos — das muss auffallen. Hinweis von immoos_builder.

    test "der erste Lauf zeichnet den Fingerabdruck still auf" do
      r = report(state: write("state", "miolimos up 1\n"), backup: healthy_backup)
      assert_empty r.alerts
      assert_includes section(r, "Schluessel"), "erstmals erfasst"
    end

    test "ein geaenderter Schluessel ist ein Alarm mit Handlungsanweisung" do
      report(state: write("state", "miolimos up 1\n"), backup: healthy_backup).alerts  # erster Lauf
      File.write(@key_path, "1" * 32)                                                   # Schluessel gewechselt
      r = report(state: write("state", "miolimos up 1\n"), backup: healthy_backup)
      assert(r.alerts.any? { |a| a.include?("hat sich geaendert") })
      assert(r.alerts.any? { |a| a.include?("Passwortmanager") }, "muss sagen, was zu tun ist")
    end

    test "ein unveraenderter Schluessel erzeugt keinen Alarm" do
      report(state: write("state", "miolimos up 1\n"), backup: healthy_backup).alerts
      r = report(state: write("state", "miolimos up 1\n"), backup: healthy_backup)
      assert_empty r.alerts
      assert_includes section(r, "Schluessel"), "unveraendert"
    end

    # #1220 (Hans): Mehrere Instanzen (miolimos_src, immoos, stocker) teilen
    # sich EINE Zustandsdatei. Unter generischen Labels ueberschrieb jede den
    # Fingerabdruck der anderen — und weil ihre Schluessel verschieden sind,
    # meldete danach jeder Lauf eine Aenderung. Genau der taegliche Fehlalarm,
    # den dieser Bericht vermeiden soll.
    test "zwei Instanzen an einer Zustandsdatei melden keine Aenderung" do
      key_b = File.join(@dir, "andere-instanz.key")
      File.write(key_b, "b" * 32)                       # bewusst ANDERER Schluessel
      state  = File.join(@dir, "gemeinsamer-keystate")
      lauf_a = -> { report(state: write("state", "miolimos up 1\n"), backup: healthy_backup,
                           keys: { "instanz_a Master-Key" => @key_path }, key_state: state) }
      lauf_b = -> { report(state: write("state", "miolimos up 1\n"), backup: healthy_backup,
                           keys: { "instanz_b Master-Key" => key_b }, key_state: state) }

      lauf_a.call.alerts   # erste Laeufe: still aufzeichnen
      lauf_b.call.alerts

      assert_empty lauf_a.call.alerts, "Instanz A darf nach dem Lauf von B keine Aenderung melden"
      assert_empty lauf_b.call.alerts, "Instanz B darf nach dem Lauf von A keine Aenderung melden"
    end

    test "die Vorgabe-Label tragen den Instanznamen, damit sie nicht kollidieren" do
      labels = DailyReport.new.instance_variable_get(:@key_files).keys
      assert(labels.all? { |l| l.start_with?(Rails.root.basename.to_s) },
             "Label muessen die Instanz benennen, sonst teilen sich zwei Instanzen einen Eintrag: #{labels}")
    end

    test "der Aenderungs-Alarm nennt den Pfad der Datei" do
      report(state: write("state", "miolimos up 1\n"), backup: healthy_backup).alerts
      File.write(@key_path, "1" * 32)
      r = report(state: write("state", "miolimos up 1\n"), backup: healthy_backup)
      assert(r.alerts.any? { |a| a.include?(@key_path) },
             "ohne Pfad ist bei mehreren Instanzen nicht erkennbar, WELCHE Datei gemeint ist")
    end

    test "ein fehlender Schluessel ist ein Alarm" do
      r = report(state: write("state", "miolimos up 1\n"), backup: healthy_backup,
                 keys: { "Master-Key" => File.join(@dir, "gibtsnicht.key") })
      assert(r.alerts.any? { |a| a.include?("fehlt") && a.include?("startet") })
    end

    test "weder Schluessel noch Fingerabdruck stehen im Bericht" do
      # Hans, 21.07.2026: „Ist es richtig, dass die Schluessel in der E-Mail
      # genannt werden?" — Der Fingerabdruck ist zwar nicht umkehrbar, gehoert
      # aber trotzdem nicht in eine Mail: Gefragt ist, OB er sich geaendert
      # hat, nicht wie er lautet.
      r = report(state: write("state", "miolimos up 1\n"), backup: healthy_backup)
      zeilen = section(r, "Schluessel")
      refute_includes zeilen, "0" * 32, "der Schluessel selbst darf nie im Bericht stehen"
      fp = Digest::SHA256.file(@key_path).hexdigest[0, 12]
      refute_includes zeilen, fp, "auch der Fingerabdruck gehoert nicht in die Mail"
      assert_includes zeilen, "erstmals erfasst"
      # In der Zustandsdatei muss er dagegen stehen — sonst gibt es keinen
      # Vergleich beim naechsten Lauf.
      assert_includes File.read(File.join(@dir, "keystate")), fp
    end


    # ── Abdeckung ─────────────────────────────────────────────────────────
    # Der Spiegelfall zu MISSING: nicht „stand in der Liste und ist weg",
    # sondern „existiert und stand nie drin". pan_rp_production war genau das.

    test "eine Datenbank, die nirgends gesichert wird, ist ein Alarm" do
      r = report(state: write("state", "miolimos up 1\n"), backup: healthy_backup,
                 dbs: -> { %w[miolimos_production pan_rp_production] })
      assert(r.alerts.any? { |a| a.include?("pan_rp_production") && a.include?("keiner Sicherung") })
      refute(r.alerts.any? { |a| a.include?("miolimos_production") },
             "eine gesicherte DB darf nicht gemeldet werden")
    end

    test "eine bewusst ausgenommene Datenbank bleibt still" do
      r = report(state: write("state", "miolimos up 1\n"), backup: healthy_backup,
                 dbs: -> { %w[miolimos_production pan_rp_production] },
                 ignoriert: %w[pan_rp_production])
      assert_empty r.alerts
      assert_includes section(r, "Abdeckung"), "bewusst nicht gesichert"
    end

    test "die Abdeckung kommt aus dem Protokoll des letzten Laufs, nicht aus einer Liste" do
      # Eine DB, die frueher einmal gesichert wurde, im letzten Lauf aber nicht
      # mehr vorkam, gilt als nicht abgedeckt.
      log = write("backup.log", <<~LOG)
        [2026-07-20 04:30:01] backup start
        [2026-07-20 04:30:06] ok altbestand_production (1 bytes)
        [2026-07-20 04:30:44] backup done (errors=0)
        [2026-07-21 04:30:01] backup start
        [2026-07-21 04:30:06] ok miolimos_production (1 bytes)
        [2026-07-21 04:30:44] backup done (errors=0)
      LOG
      r = report(state: write("state", "miolimos up 1\n"), backup: log,
                 dbs: -> { %w[miolimos_production altbestand_production] })
      assert(r.alerts.any? { |a| a.include?("altbestand_production") })
    end

    test "Datei-Archive zaehlen nicht als Datenbank-Abdeckung" do
      log = write("backup.log", <<~LOG)
        [2026-07-21 04:30:01] backup start
        [2026-07-21 04:30:06] ok stocker-data (10093 bytes verschluesselt)
        [2026-07-21 04:30:44] backup done (errors=0)
      LOG
      r = report(state: write("state", "miolimos up 1\n"), backup: log,
                 dbs: -> { %w[stocker_production] })
      assert(r.alerts.any? { |a| a.include?("stocker_production") },
             "ein -data-Archiv darf die gleichnamige DB nicht als gesichert ausweisen")
    end


    test "die eingetragene Vorgabe-Ausnahme wirkt auch ohne Parameter" do
      # Wenn jemand die Ausnahme aus der Vorgabe entfernt, faellt es hier auf --
      # und nicht erst dadurch, dass Hans wieder eine Meldung bekommt, die er
      # schon einmal beantwortet hat.
      # ohne `ignored_databases` — genau darum geht es hier
      r = DailyReport.new(**neutrale_args(
        state_file: write("state", "miolimos up 1\n"),
        backup_log: healthy_backup,
        key_state_file: File.join(@dir, "keystate2"),
        database_probe: -> { %w[pan_rp_production] }
      ))
      assert_empty r.alerts
      assert_includes r.sections.find { |x| x.title == "Abdeckung" }.lines.join("\n"),
                      "bewusst nicht gesichert"
    end


    test "ein Datenverzeichnis ohne Sicherung ist ein Alarm" do
      reg = write("registry", "miolimos\t3007\t/home/hans/miolimos\nneu\t3200\t/home/hans/neu_data\n")
      log = write("backup.log", <<~LOG)
        [2026-07-21 04:30:01] backup start
        [2026-07-21 04:30:06] ok miolimos-data (68 bytes verschluesselt)
        [2026-07-21 04:30:44] backup done (errors=0)
      LOG
      r = report(state: write("state", "miolimos up 1\n"), backup: log, registry: reg)
      assert(r.alerts.any? { |a| a.include?("neu") && a.include?("/home/hans/neu_data") })
      refute(r.alerts.any? { |a| a.include?("/home/hans/miolimos)") },
             "ein gesichertes Verzeichnis darf nicht gemeldet werden")
    end

    test "eine Instanz ohne eigenes Datenverzeichnis wird uebersprungen" do
      # monica setzt kein MIOLIMOS_DATA_PATH und teilt sich das Verzeichnis
      # von miolimos — ein leeres Feld darf keinen Alarm ausloesen.
      reg = write("registry", "miolimos\t3007\t/home/hans/miolimos\nmonica\t3008\t\n")
      log = write("backup.log", <<~LOG)
        [2026-07-21 04:30:01] backup start
        [2026-07-21 04:30:06] ok miolimos-data (68 bytes verschluesselt)
        [2026-07-21 04:30:44] backup done (errors=0)
      LOG
      r = report(state: write("state", "miolimos up 1\n"), backup: log, registry: reg)
      assert_empty r.alerts
      refute_includes section(r, "Abdeckung"), "monica"
    end

    test "ohne Registry bleibt der Verzeichnisteil einfach leer" do
      r = report(state: write("state", "miolimos up 1\n"), backup: healthy_backup)
      assert_empty r.alerts.select { |a| a.include?("Datenverzeichnis") }
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
