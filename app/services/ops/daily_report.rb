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
      key_files: { "Master-Key" => Rails.root.join("config/master.key").to_s,
                   "Credentials" => Rails.root.join("config/credentials.yml.enc").to_s },
      key_state_file: "/home/hans/.local/state/miolimos-watch/keys",
      database_probe: method(:production_databases),
      # Ausdrueckliche Ausnahmen von der Abdeckungspruefung. Hier steht die
      # ENTSCHEIDUNG, nicht die Bequemlichkeit: Wer eine Produktivdatenbank
      # hier eintraegt, erklaert, dass ihr Verlust hinnehmbar ist. Alles, was
      # nicht drinsteht und nicht gesichert wird, meldet sich jeden Morgen.
      #
      #   pan_rp_production — Hans, 21.07.2026, auf Rueckfrage: „Nein, PanRP
      #   braucht nicht gesichert zu werden. Das war nur ein Experiment."
      ignored_databases: %w[pan_rp_production],
      event_log:  "/home/hans/log/miolimos-service-watch.log",
      backup_log: "/home/hans/log/miolimos-db-backup.log",
      repos:      { "App-Code" => "/home/hans/miolimos_src",
                    "Wissensdateien" => "/home/hans/miolimos" },
      repo_probe: method(:git_state),
      now: Time.current
    )
      @state_file = state_file
      @key_files      = key_files
      @key_state_file = key_state_file
      @database_probe    = database_probe
      @ignored_databases = ignored_databases
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
          mail_section(alerts),
          keys_section(alerts),
          coverage_section(alerts)
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
    # KORREKTUR (21.07.2026, beim ersten Lauf gegen eine WIEDER VERBUNDENE
    # Credential aufgefallen): `expires_at` ist NICHT die Gueltigkeit des
    # Zugangs, sondern die des kurzlebigen Zugriffstokens — es laeuft im
    # Stundentakt ab und wird von GmailSender#refresh_token_if_needed! ueber
    # den refresh_token selbsttaetig erneuert. Eine Warnung „laeuft demnaechst
    # ab" haette deshalb JEDEN Tag gefeuert, an dem alles in Ordnung ist.
    #
    # Das ist die Sorte Fehlalarm, die ein Ueberwachungssystem umbringt:
    # taeglicher Alarm ohne Anlass, bis niemand mehr hinsieht — und dann faellt
    # der eine echte auch nicht mehr auf. Geprueft werden deshalb nur die
    # Zustaende, die ein Mensch beheben muss: kein Konto, Konto inaktiv, oder
    # abgelaufen OHNE Erneuerungs-Token (dann hilft nur neu verbinden).
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
      elsif cred.refresh_token.blank?
        lines << "#{cred.email_address}: kein Erneuerungs-Token"
        alerts << "Der Google-Zugang #{cred.email_address} hat keinen Erneuerungs-Token — " \
                  "sobald das Zugriffstoken ablaeuft, steht der Mailversand. Neu verbinden."
      else
        lines << "#{cred.email_address}: aktiv (Zugriffstoken erneuert sich selbst)"
      end

      Section.new(title: "Postausgang", lines: lines)
    rescue StandardError => e
      Section.new(title: "Postausgang", lines: [ "nicht feststellbar (#{e.class})" ])
    end


    # ── Schluessel ───────────────────────────────────────────────────────
    # config/master.key und credentials.yml.enc liegen BEWUSST nicht im
    # Backup: laegen sie im Datenarchiv, schloesse die eine Backup-Passphrase
    # alles auf — Daten und Schluessel im selben Behaelter. Ihre einzige
    # Zweitschrift ist die Kopie im Passwortmanager.
    #
    # Genau daraus folgt der Fall, den dieser Abschnitt sichtbar macht: Wird
    # der Schluessel gewechselt, wird die Kopie im Passwortmanager
    # stillschweigend wertlos. Niemand merkt es — bis zum Restore, bei dem der
    # Dump sauber zurueckgeht und die Instanz trotzdem nicht bootet.
    #
    # Gespeichert wird nur ein Fingerabdruck, nie der Schluessel selbst. Beim
    # ersten Lauf wird er still aufgezeichnet (nie gesehen = still, wie
    # ueberall hier); erst eine AENDERUNG ist laut.
    # Hinweis von immoos_builder, 2026-07-21.
    def keys_section(alerts)
      lines = []
      previous = read_key_state
      current  = {}

      @key_files.each do |label, path|
        unless File.exist?(path)
          alerts << "#{label} fehlt (#{path}) — die Instanz startet ohne ihn nicht."
          lines << "#{label}: FEHLT"
          next
        end

        fp = Digest::SHA256.file(path).hexdigest[0, 12]
        current[label] = fp

        if previous[label].nil?
          lines << "#{label}: #{fp} (erstmals erfasst)"
        elsif previous[label] != fp
          alerts << "#{label} hat sich geaendert (#{previous[label]} → #{fp}). "                     "Die Kopie im Passwortmanager ist damit veraltet und muss aufgefrischt werden — "                     "sonst startet eine Wiederherstellung nicht."
          lines << "#{label}: GEAENDERT (#{previous[label]} → #{fp})"
        else
          lines << "#{label}: #{fp} unveraendert"
        end
      end

      write_key_state(previous.merge(current))
      lines << ""
      lines << "Diese Dateien liegen nicht im Backup — ihre Zweitschrift ist der Passwortmanager."
      Section.new(title: "Schluessel", lines: lines)
    rescue StandardError => e
      Section.new(title: "Schluessel", lines: [ "nicht feststellbar (#{e.class})" ])
    end

    def read_key_state
      return {} unless File.exist?(@key_state_file)
      File.readlines(@key_state_file, chomp: true).to_h do |line|
        label, fp = line.split("\t", 2)
        [ label, fp ]
      end
    rescue StandardError
      {}
    end

    def write_key_state(map)
      FileUtils.mkdir_p(File.dirname(@key_state_file))
      File.write(@key_state_file, map.map { |k, v| "#{k}\t#{v}" }.join("\n"))
    rescue StandardError
      nil # Ein nicht schreibbarer Zustand darf den Bericht nicht verhindern.
    end


    # ── Abdeckung ────────────────────────────────────────────────────────
    # Das Gegenstueck zur MISSING-Meldung aus #1064.
    #
    # Dort geht es um „stand in der Liste und ist weg". Hier um den
    # Spiegelfall, der bis heute gar nicht geprueft wurde: „existiert auf der
    # Maschine und stand nie in der Liste". Eine neu angelegte Produktivdaten-
    # bank wird schlicht nie gesichert, ohne dass irgendetwas auffiele — kein
    # Fehler, keine Zeile im Log, denn das Backup weiss ja nichts von ihr.
    # Genau so lief die immoOS-Instanz von Juli an ausserhalb jeder Sicherung.
    #
    # Abgeglichen wird gegen das, was der letzte Lauf TATSAECHLICH angefasst
    # hat (die ok/skip/MISSING-Zeilen im Protokoll) — nicht gegen die Liste im
    # Skript. Eine Liste sagt, was gemeint war; das Protokoll sagt, was
    # geschehen ist.
    #
    # GRENZE, ausdruecklich: geprueft werden nur Datenbanken. Ein
    # Datenverzeichnis einer neuen Instanz faellt hier nicht auf.
    def coverage_section(alerts)
      lines = []
      vorhanden = Array(@database_probe.call)
      if vorhanden.empty?
        return Section.new(title: "Abdeckung", lines: [ "keine Datenbanken feststellbar" ])
      end

      abgedeckt = covered_databases

      vorhanden.sort.each do |db|
        if abgedeckt.include?(db)
          lines << "#{db}: gesichert"
        elsif @ignored_databases.include?(db)
          lines << "#{db}: bewusst nicht gesichert"
        else
          alerts << "#{db} existiert, wird aber von keiner Sicherung erfasst."
          lines << "#{db}: NICHT GESICHERT"
        end
      end

      Section.new(title: "Abdeckung", lines: lines)
    rescue StandardError => e
      Section.new(title: "Abdeckung", lines: [ "nicht feststellbar (#{e.class})" ])
    end

    # Was der letzte Lauf angefasst hat. Die Datei-Archive (…-data) gehoeren
    # nicht dazu — hier geht es um Datenbanken.
    def covered_databases
      return [] unless File.exist?(@backup_log)
      zeilen = tail(@backup_log, 400)
      start  = zeilen.rindex { |l| l.include?("backup start") }
      lauf   = start ? zeilen[start..] : zeilen
      lauf.filter_map { |l|
        m = l.match(/\]\s+(?:ok|skip|MISSING)\s+(\S+)/)
        name = m && m[1]
        name unless name.nil? || name.end_with?("-data")
      }.uniq
    end

    def production_databases
      ActiveRecord::Base.connection
        .select_values("SELECT datname FROM pg_database WHERE datistemplate = false")
        .select { |d| d.end_with?("_production") }
    rescue StandardError
      []
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
