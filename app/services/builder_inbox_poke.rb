# #382 (Hans, 2026-06-03): Stupst einen AgentActor (Builder) zu einem
# Inbox-Lauf an — setzt das `inbox_run_requested_at`-Flag (das der
# Heartbeat als pending_trigger liest) UND schreibt direkt in seine
# tmux-Session, damit er sofort reagiert. DAS ist der Poke-Pfad: das
# Anstupsen ist event-getrieben (Publish/Antwort/@-Mention/Trigger-Button),
# es gibt KEINEN aktiven Cron-Tick (seit #441 ist die Crontab-Zeile nur noch
# Registry für Session+Prompt, siehe `wiring_for`). Aus
# BuilderTriggersController (#278) extrahiert, damit das automatische
# Anstupsen bei Publish/Antwort denselben Pfad nutzt.
#
# Design (Hans-Spec #382):
#  - generischer Poke (kein „spring auf Item X"): der Builder arbeitet
#    ohnehin alle offenen Tasks ab; der Item-Hinweis kommt nur als
#    Kontext (`note`) mit an die Prompt.
#  - debounce/coalesce: mehrere Pokes in kurzer Folge loesen nur EINEN
#    tmux-Send aus (ein Lauf nimmt eh alles mit). Der manuelle Button
#    ruft mit debounce: false (soll immer feuern).
#  - kein Selbst-Poke: Aufrufer filtern `agent != current_actor`.
class BuilderInboxPoke
  DEBOUNCE = 45.seconds

  # #1586 (Hans): „Wird dadurch die Arbeit des Agenten unterbrochen?" — Ein
  # Poke in eine arbeitende Sitzung bricht nichts ab, landet aber mitten im
  # laufenden Schritt. Deshalb: Antwort auf die Aufgabe, an der der Agent
  # gerade sitzt (WIP), sofort — sie kann eine Korrektur vor dem Deploy sein.
  # Alles andere setzt den Auslöser sofort, eingetippt wird aber erst, wenn
  # die Sitzung ruhig ist (DeferredInboxPokeJob). „Beschäftigt" liest die
  # Sitzung selbst ab, nicht den WIP-Marker: Der kann veralten, und ohne
  # Cron-Rückfall (#441) wären Auslöser dann dauerhaft verschluckt.
  DEFER_RECHECK = 30.seconds
  DEFER_MAX     = 1.hour
  # Claude Code zeigt das in der Fußzeile, solange ein Schritt läuft — auch
  # während eines Vordergrund-Befehls. Beim Warten auf einen Hintergrund-Lauf
  # nach Schrittende steht es NICHT da (gemessen 14.09.2026, #1586).
  BUSY_MARKER   = "esc to interrupt".freeze

  # #512 (Hans, 2026-06-04): `clear:` schickt ein `/clear` Enter vor dem
  # Inbox-Check-Prompt — frischer Kontext (z. B. für eine neue Recherche,
  # damit der Agent sauber aus dem Handbuch bootstrappt statt alten Kontext
  # mitzuschleppen).
  # #1586: `task:` = die Aufgabe, um die es geht (Antwort/Veröffentlichung) —
  # ist sie die WIP-Aufgabe des Agenten, wird sofort zugestellt. `sofort:` =
  # ausdrücklicher Knopfdruck, wartet nie.
  def self.poke(actor:, note: nil, debounce: true, clear: false, task: nil, sofort: false)
    new(actor: actor, note: note, debounce: debounce, clear: clear, task: task, sofort: sofort).call
  end

  # #1586: Steht in der Fußzeile der Sitzung, dass gerade ein Schritt läuft?
  # Pure Funktion fürs Testen.
  def self.busy_pane?(text)
    text.to_s.include?(BUSY_MARKER)
  end

  # Liest die Sitzung des Agenten ab. Im Zweifel „ruhig" — lieber einmal zu
  # früh tippen (wie vor #1586) als eine Nachricht liegen lassen.
  def self.session_busy?(actor)
    return false if Rails.env.test?
    session, = wiring_for(actor)
    return false unless session
    out = IO.popen(["tmux", "capture-pane", "-t", session, "-p"], err: File::NULL, &:read)
    busy_pane?(out)
  rescue StandardError => e
    Rails.logger.warn "BuilderInboxPoke.session_busy?(id=#{actor&.id}): #{e.class}: #{e.message}"
    false
  end

  # #518 (Hans, 2026-06-05): Agenten, die in einem Reply-KI per @-Mention
  # angesprochen sind, anstupsen — damit eine Diskussion AN einem KI den
  # Agenten genauso erreicht wie eine Antwort an einer Aufgabe. Mentions
  # liegen nach FileProxy.create (ActorMentions.sync) bereits vor.
  def self.poke_mentioned_agents(reply, except: nil, note: nil)
    ids = ActorMention.where(knowledge_item_uuid: reply.uuid).pluck(:actor_id)
    ids -= [except.id] if except
    AgentActor.where(id: ids, active: true).find_each do |agent|
      poke(actor: agent, note: note, debounce: false)
    end
  end

  # #587 (Hans, 2026-06-10): @-Mentions im BODY normaler KIs pokten nie —
  # nur der Reply-Pfad (Controller) tat das. FileProxy::Writer ruft das
  # hier mit den NEU hinzugekommenen Mention-Actor-IDs (sync_for-Delta) —
  # dadurch pokt eine Mention genau einmal, auch wenn das KI danach noch
  # zehnmal editiert wird. Replies pokt weiterhin der Controller (mit
  # spezifischerer Note), daher hier ausgeschlossen.
  def self.poke_body_mentions(item, new_actor_ids, except: nil)
    return if item.nil? || item.item_type.to_s == "reply"
    ids = Array(new_actor_ids)
    ids -= [except.id] if except.is_a?(Actor)
    return if ids.empty?
    AgentActor.where(id: ids, active: true).find_each do |agent|
      poke(actor: agent, note: "@-Erwähnung in KI „#{item.title}“", debounce: false)
    end
  end

  def initialize(actor:, note:, debounce:, clear: false, task: nil, sofort: false)
    @actor    = actor
    @note     = note
    @debounce = debounce
    @clear    = clear
    @task     = task
    @sofort   = sofort
  end

  # Liefert true, wenn tatsaechlich gepokt (Flag gesetzt + tmux geschickt oder
  # aufgeschoben), false bei Coalesce/kein Agent. Wirft nie — Fehler werden geloggt.
  def call
    return false unless @actor.is_a?(AgentActor)
    if @debounce && (last = @actor.inbox_run_requested_at) && last > DEBOUNCE.ago
      return false   # kurz zuvor schon gepokt -> coalesce
    end
    # Auf Mikrosekunden gekürzt, wie Postgres speichert — der aufgeschobene
    # Job erkennt „sein" Flag am exakten Wert.
    jetzt = Time.current.floor(6)
    @actor.update_column(:inbox_run_requested_at, jetzt)
    if sofort_zustellen?
      send_tmux
    else
      DeferredInboxPokeJob.set(wait: DEFER_RECHECK)
                          .perform_later(@actor.id, @note, jetzt.iso8601(6), Time.current.iso8601)
    end
    true
  rescue StandardError => e
    Rails.logger.warn "BuilderInboxPoke(id=#{@actor&.id}): #{e.class}: #{e.message}"
    false
  end

  # tmux send-keys mit 2-Schritt-Pattern (Text + Enter, dazwischen sleep) —
  # async im Thread, damit der HTTP-Request nicht 1s blockiert. Session +
  # Prompt kommen aus der Crontab-Zeile des Actors (Marker `(id=<id>)`).
  # #1586: Klassenmethode, damit auch DeferredInboxPokeJob sie nutzt.
  def self.tippen(actor, note: nil, clear: false)
    # Test-Suite läuft auf derselben Maschine wie die echten tmux-Sessions —
    # ein Test-Actor mit zufällig passender id würde sonst REAL in die
    # Session des Builders tippen (passiert beim #587-Deploy-Gate).
    return if Rails.env.test?
    session, prompt = wiring_for(actor)
    unless session
      Rails.logger.warn "BuilderInboxPoke: kein Crontab-Eintrag fuer (id=#{actor.id})"
      return
    end
    full = note.present? ? "#{prompt} [Auslöser: #{note}]" : prompt
    Thread.new do
      begin
        # #512: optional erst /clear (frischer Kontext), dann den Prompt.
        if clear
          system("tmux", "send-keys", "-t", session, "-l", "/clear")
          sleep 0.3
          system("tmux", "send-keys", "-t", session, "Enter")
          sleep 1
        end
        system("tmux", "send-keys", "-t", session, "-l", full)
        sleep 1
        system("tmux", "send-keys", "-t", session, "Enter")
        # #815: Sicherheits-Enter. Fällt das erste Enter in einen Busy-/
        # Render-Moment der Claude-Session, bleibt der Prompt unsubmittet
        # im Eingabefeld liegen (beim immoos_builder zweimal beobachtet).
        # Ein zweites Enter nach Wartezeit submittet dann; war das erste
        # erfolgreich, ist es ein No-Op auf leerem Eingabefeld.
        sleep 2
        system("tmux", "send-keys", "-t", session, "Enter")
      rescue StandardError => e
        Rails.logger.warn "BuilderInboxPoke tmux (id=#{actor.id}): #{e.class}: #{e.message}"
      end
    end
  end

  private

  def sofort_zustellen?
    return true if @sofort
    return true if @task && @task.wip_actor_id == @actor.id
    !session_busy?
  end

  def session_busy?
    self.class.session_busy?(@actor)
  end

  def send_tmux
    self.class.tippen(@actor, note: @note, clear: @clear)
  end

  # #639: Verdrahtung eines Agenten = Crontab-Zeile mit Marker
  # `(id=<id>)` + tmux-Session + Prompt. Auch AUSKOMMENTIERTE Zeilen
  # zählen (die Zeile ist seit #441/2026-05-31 bewusst nur noch
  # Registry für den Poke, kein aktiver Cron-Tick mehr). Public, damit
  # das Agenten-Blade die Verdrahtung anzeigen kann.
  def self.wiring_for(actor)
    parse_wiring(`crontab -l 2>/dev/null`, actor.id)
  end

  # Pure Funktion fürs Testen — [session, prompt] oder nil.
  def self.parse_wiring(crontab_text, actor_id)
    crontab_text.to_s.each_line do |line|
      next unless line.include?("(id=#{actor_id})")
      session_match = line.match(/tmux send-keys -t (\S+)/)
      prompt_match  = line.match(/'([^']+)'/)
      return [session_match[1], prompt_match[1]] if session_match && prompt_match
    end
    nil
  end
end
