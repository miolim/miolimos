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

  # #512 (Hans, 2026-06-04): `clear:` schickt ein `/clear` Enter vor dem
  # Inbox-Check-Prompt — frischer Kontext (z. B. für eine neue Recherche,
  # damit der Agent sauber aus dem Handbuch bootstrappt statt alten Kontext
  # mitzuschleppen).
  def self.poke(actor:, note: nil, debounce: true, clear: false)
    new(actor: actor, note: note, debounce: debounce, clear: clear).call
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

  def initialize(actor:, note:, debounce:, clear: false)
    @actor    = actor
    @note     = note
    @debounce = debounce
    @clear    = clear
  end

  # Liefert true, wenn tatsaechlich gepokt (Flag gesetzt + tmux geschickt),
  # false bei Coalesce/kein Agent. Wirft nie — Fehler werden geloggt.
  def call
    return false unless @actor.is_a?(AgentActor)
    if @debounce && (last = @actor.inbox_run_requested_at) && last > DEBOUNCE.ago
      return false   # kurz zuvor schon gepokt -> coalesce
    end
    @actor.update_column(:inbox_run_requested_at, Time.current)
    send_tmux
    true
  rescue StandardError => e
    Rails.logger.warn "BuilderInboxPoke(id=#{@actor&.id}): #{e.class}: #{e.message}"
    false
  end

  private

  # tmux send-keys mit 2-Schritt-Pattern (Text + Enter, dazwischen sleep) —
  # async im Thread, damit der HTTP-Request nicht 1s blockiert. Session +
  # Prompt kommen aus der Crontab-Zeile des Actors (Marker `(id=<id>)`).
  def send_tmux
    # Test-Suite läuft auf derselben Maschine wie die echten tmux-Sessions —
    # ein Test-Actor mit zufällig passender id würde sonst REAL in die
    # Session des Builders tippen (passiert beim #587-Deploy-Gate).
    return if Rails.env.test?
    session, prompt = cron_send_keys_for(@actor)
    unless session
      Rails.logger.warn "BuilderInboxPoke: kein Crontab-Eintrag fuer (id=#{@actor.id})"
      return
    end
    full = @note.present? ? "#{prompt} [Auslöser: #{@note}]" : prompt
    Thread.new do
      begin
        # #512: optional erst /clear (frischer Kontext), dann den Prompt.
        if @clear
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
        Rails.logger.warn "BuilderInboxPoke tmux (id=#{@actor.id}): #{e.class}: #{e.message}"
      end
    end
  end

  def cron_send_keys_for(actor)
    self.class.wiring_for(actor)
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
