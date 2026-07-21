module Ops
  # Taeglicher Betriebsbericht (#1076).
  #
  # Die Erkenntnis aus #1074, die diesen Dienst ausgeloest hat: Am 21.07.2026
  # kamen an einem Vormittag drei Ausfaelle zusammen, die alle dieselbe Form
  # hatten — etwas hat sich lautlos geaendert, und die zustaendige Pruefung
  # konnte den Uebergang nicht sehen oder meldete ihn nur an eine Stelle, an
  # die niemand schaut:
  #
  #   - der stuendliche Code-Push nach GitHub war seit vier Wochen tot
  #     (715 Fehlschlaege, brav ins Log geschrieben, nie gelesen)
  #   - eine Produktivinstanz war 1:41 h aus (systemd meldet das nirgends)
  #   - das DB-Backup haette eine umbenannte DB stillschweigend uebersprungen
  #
  # Gegenmittel ist nicht noch ein Log, sondern ein Bericht, der von selbst
  # dorthin kommt, wo Hans hinschaut. Er geht JEDEN Tag raus, auch wenn alles
  # gruen ist — denn dann ist sein AUSBLEIBEN das Signal. Ein Alarm, der nur
  # im Fehlerfall kaeme, waere von einem defekten Alarm nicht zu unterscheiden.
  class DailyReport
    Section = Struct.new(:title, :lines, keyword_init: true)

    # Alles ueber Parameter, damit der Test nicht auf die echte Maschine
    # zugreift (und der Bericht auf einer anderen Installation umkonfiguriert
    # werden kann, ohne den Code anzufassen).
    # Wie lange darf Arbeit unveroeffentlicht liegen, bevor es auffaellt?
    # Der Push-Cron laeuft stuendlich; drei Stunden lassen Raum fuer einen
    # ausgefallenen Lauf, ohne vier Wochen zu verschlafen.
    PUSH_GRACE = 3.hours

    def initialize(
      state_file: "/home/hans/.local/state/miolimos-watch/state",
      event_log:  "/home/hans/log/miolimos-service-watch.log",
      backup_log: "/home/hans/log/miolimos-db-backup.log",
      repos:      { "App-Code" => "/home/hans/miolimos_src",
                    "Wissensdateien" => "/home/hans/miolimos" },
      repo_probe: method(:git_state),
      now: Time.current
    )
      @state_file = state_file
      @event_log  = event_log
      @backup_log = backup_log
      @repos      = repos
      @repo_probe = repo_probe
      @now        = now
    end

    def alerts = @alerts ||= build.first
    def sections = @sections ||= build.last

    def subject
      if alerts.empty?
        "miolimOS Betriebsbericht #{@now.strftime('%d.%m.%Y')} — alles gruen"
      else
        # Kein `pluralize` — der englische Inflector macht daraus
        # „Auffaelligkeits".
        wort = alerts.size == 1 ? "Auffaelligkeit" : "Auffaelligkeiten"
        "miolimOS Betriebsbericht #{@now.strftime('%d.%m.%Y')} — #{alerts.size} #{wort}"
      end
    end

    private

    def build
      @build ||= begin
        alerts = []
        sections = [
          services_section(alerts),
          backup_section(alerts),
          push_section(alerts),
          mail_section(alerts)
        ]
        [ alerts, sections ]
      end
    end

    # ── Dienste ──────────────────────────────────────────────────────────
    def services_section(alerts)
      lines = []
      entries = read_state

      if entries.empty?
        alerts << "Der Waechter hat noch nie gelaufen — keine Zustandsdatei unter #{@state_file}."
        lines << "keine Daten (Waechter noch nicht gelaufen?)"
      else
        entries.each do |name, status, last_ok|
          case status
          when "up"
            lines << "#{name}: laeuft"
          when "down"
            seit = last_ok.to_i.positive? ? " (zuletzt erreichbar #{Time.zone.at(last_ok).strftime('%d.%m. %H:%M')})" : ""
            alerts << "#{name} antwortet nicht#{seit}."
            lines << "#{name}: AUSGEFALLEN#{seit}"
          else
            # Noch nie erreichbar gewesen: bewusst kein Alarm, aber sichtbar —
            # sonst faellt eine Instanz, die nie hochkam, dauerhaft durch.
            lines << "#{name}: noch nie erreichbar gesehen"
          end
        end
      end

      recent = recent_events
      if recent.any?
        lines << ""
        lines << "Ereignisse der letzten 24 Stunden:"
        recent.each { |e| lines << "  #{e}" }
      else
        lines << ""
        lines << "keine Zustandswechsel in den letzten 24 Stunden"
      end

      Section.new(title: "Dienste", lines: lines)
    end

    def read_state
      return [] unless File.exist?(@state_file)
      File.readlines(@state_file, chomp: true).filter_map do |line|
        name, status, last_ok = line.split
        next if name.blank?
        [ name, status, last_ok.to_i ]
      end
    end

    def recent_events
      return [] unless File.exist?(@event_log)
      cutoff = @now - 24.hours
      tail(@event_log, 200).select { |l| (t = log_time(l)) && t >= cutoff }
    end

    # ── Datensicherung ───────────────────────────────────────────────────
    def backup_section(alerts)
      lines = []
      unless File.exist?(@backup_log)
        alerts << "Kein Backup-Protokoll unter #{@backup_log} gefunden."
        return Section.new(title: "Datensicherung", lines: [ "kein Protokoll gefunden" ])
      end

      recent = tail(@backup_log, 400)
      done = recent.reverse.find { |l| l.include?("backup done") }

      if done.nil?
        alerts << "Im Backup-Protokoll steht kein abgeschlossener Lauf."
        lines << "kein abgeschlossener Lauf im Protokoll"
      else
        t = log_time(done)
        age_h = t ? ((@now - t) / 3600).floor : nil
        if age_h.nil? || age_h > 26
          alerts << "Die letzte Datensicherung ist #{age_h ? "#{age_h} Stunden" : 'unbekannt'} alt — erwartet wird taeglich."
        end
        lines << "letzter Lauf: #{t&.strftime('%d.%m.%Y %H:%M') || 'unbekannt'}#{age_h ? " (vor #{age_h} h)" : ''}"

        if done.include?("errors=0")
          lines << "Ergebnis: fehlerfrei"
        else
          alerts << "Die letzte Datensicherung meldet Fehler."
          lines << "Ergebnis: MIT FEHLERN"
        end
      end

      # Die Zeilen des letzten Laufs mit Ergebnis je Datenbank.
      last_start = recent.rindex { |l| l.include?("backup start") }
      if last_start
        run = recent[last_start..]
        %w[ok skip MISSING FAILED].each do |kind|
          run.grep(/\] #{kind} /).each do |l|
            lines << "  #{l.sub(/^\[[^\]]*\]\s*/, '')}"
            alerts << "Datensicherung: #{l.sub(/^\[[^\]]*\]\s*/, '')}" if %w[MISSING FAILED].include?(kind)
          end
        end
      end

      Section.new(title: "Datensicherung", lines: lines)
    end

    # ── Code-Sicherung ───────────────────────────────────────────────────
    # Der Fall, der vier Wochen unbemerkt blieb (Push nach GitHub abgelehnt,
    # weil ein Bot direkt in die Fernkopie committet hatte).
    #
    # Gefragt wird BEWUSST nicht das Push-Protokoll, sondern das Repository
    # selbst. Der Push-Cron schreibt naemlich nur, wenn er etwas zu tun hatte;
    # ein erfolgreicher Leerlauf hinterlaesst keine Zeile. Die letzte Zeile
    # eines solchen Protokolls kann also monatelang „FAILED" lauten, obwohl
    # laengst wieder alles gepusht wird — und umgekehrt. Die einzige Frage,
    # die zaehlt, ist: liegt meine Arbeit auch woanders? Das beantwortet
    # `rev-list @{u}..HEAD`, und zwar unabhaengig davon, wer wann was
    # protokolliert hat.
    def push_section(alerts)
      lines = []
      @repos.each do |label, path|
        state = @repo_probe.call(path)

        case state[:status]
        when :missing
          alerts << "#{label}: kein Git-Repository unter #{path} gefunden."
          lines << "#{label}: kein Repository unter #{path}"
        when :no_remote
          alerts << "#{label}: hat keine Fernkopie — die Daten liegen nur auf dieser Maschine."
          lines << "#{label}: KEINE Fernkopie eingerichtet"
        when :error
          alerts << "#{label}: Zustand nicht feststellbar (#{state[:detail]})."
          lines << "#{label}: nicht feststellbar"
        when :synced
          lines << "#{label}: vollstaendig auf GitHub"
        when :ahead
          ahead = state[:ahead]
          oldest = state[:oldest_unpushed]
          age = oldest ? (@now - oldest) : nil
          if age.nil? || age > PUSH_GRACE
            alerts << "#{label}: #{ahead} #{ahead == 1 ? 'Commit liegt' : 'Commits liegen'} nur auf dieser Maschine" \
                      "#{oldest ? ", der aelteste seit #{oldest.strftime('%d.%m.%Y %H:%M')}" : ''}."
            lines << "#{label}: #{ahead} NICHT gesichert#{oldest ? " (aeltester #{oldest.strftime('%d.%m. %H:%M')})" : ''}"
          else
            # Frisch committet, der stuendliche Push kommt noch.
            lines << "#{label}: #{ahead} Commit(s) warten auf den naechsten Push"
          end
        end
      end
      Section.new(title: "Code-Sicherung nach GitHub", lines: lines)
    end

    # ── Postausgang ──────────────────────────────────────────────────────
    # Der Bericht prueft seinen EIGENEN Zustellweg, und das ist keine
    # Spielerei: Am 21.07.2026 war die Google-Credential seit zehn Tagen
    # abgelaufen — miolimOS konnte keine einzige Mail verschicken, auch keinen
    # Portal-Magic-Link, und nichts hat das gemeldet. Ein Ueberwachungssystem,
    # dessen einziger Kanal still kaputtgeht, ueberwacht nichts mehr.
    #
    # Deshalb steht die Ablauf-Warnung hier VOR dem Ablauf: Ein Token, das in
    # zwei Tagen faellig ist, ist noch reparierbar; eines, das gestern abgelaufen
    # ist, hat schon Post verschluckt.
    def mail_section(alerts)
      lines = []
      cred = OauthCredential.where(provider: "google").order(:id).last

      if cred.nil?
        lines << "kein Google-Konto verbunden — Mailversand nicht moeglich"
        alerts << "Es ist kein Google-Konto verbunden; miolimOS kann keine Mails verschicken."
      elsif !cred.active?
        lines << "#{cred.email_address}: NICHT AKTIV"
        alerts << "Der Mailversand ist abgeschaltet: das Google-Konto #{cred.email_address} ist nicht mehr aktiv" \
                  "#{cred.expires_at ? " (abgelaufen am #{cred.expires_at.strftime('%d.%m.%Y')})" : ''}. " \
                  "Unter Einstellungen → Konten neu verbinden — betrifft auch Portal-Mails und Magic-Links."
      elsif cred.expired?
        lines << "#{cred.email_address}: Zugang abgelaufen"
        alerts << "Der Google-Zugang #{cred.email_address} ist abgelaufen und muss neu verbunden werden."
      elsif cred.expires_at && cred.expires_at < @now + 3.days
        lines << "#{cred.email_address}: laeuft ab am #{cred.expires_at.strftime('%d.%m.%Y %H:%M')}"
        alerts << "Der Google-Zugang #{cred.email_address} laeuft am " \
                  "#{cred.expires_at.strftime('%d.%m.%Y')} ab — vorher neu verbinden."
      else
        lines << "#{cred.email_address}: aktiv#{cred.expires_at ? ", gueltig bis #{cred.expires_at.strftime('%d.%m.%Y %H:%M')}" : ''}"
      end

      Section.new(title: "Postausgang", lines: lines)
    rescue StandardError => e
      Section.new(title: "Postausgang", lines: [ "nicht feststellbar (#{e.class})" ])
    end

    # Zustand eines Arbeitsverzeichnisses gegenueber seiner Fernkopie.
    # Ausgelagert und ueber `repo_probe` austauschbar, damit der Test die
    # Faelle durchspielen kann, ohne fuer jeden ein echtes Repo zu bauen.
    def git_state(path)
      return { status: :missing } unless Dir.exist?(File.join(path, ".git"))

      upstream = git(path, "rev-parse", "--abbrev-ref", "@{u}")
      return { status: :no_remote } if upstream.nil?

      ahead = git(path, "rev-list", "--count", "@{u}..HEAD").to_i
      return { status: :synced } if ahead.zero?

      # Zeitstempel des aeltesten noch nicht gepushten Commits.
      oldest = git(path, "log", "--format=%ct", "@{u}..HEAD")&.split&.last
      { status: :ahead, ahead: ahead, oldest_unpushed: oldest && Time.zone.at(oldest.to_i) }
    rescue StandardError => e
      { status: :error, detail: e.class.name }
    end

    def git(path, *args)
      out = IO.popen([ "git", "-C", path, *args ], err: File::NULL, &:read)
      $?&.success? ? out.strip.presence : nil
    end

    # ── Hilfsmittel ──────────────────────────────────────────────────────
    def tail(path, lines)
      File.readlines(path, chomp: true).last(lines) || []
    rescue SystemCallError
      []
    end

    # Alle Betriebsprotokolle beginnen mit "[YYYY-MM-DD HH:MM:SS] ".
    def log_time(line)
      m = line.match(/\A\[(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})\]/)
      m && Time.zone.parse(m[1])
    rescue ArgumentError
      nil
    end
  end
end
