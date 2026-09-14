# #1586 (Hans): „Das Veröffentlichen einer Aufgabe oder Antwort triggert
# automatisch einen Inbox-Lauf. Wird dadurch die Arbeit des Agenten
# unterbrochen und seine Konzentration geschwächt?" — „OK, dann bitte so bauen."
#
# Der aufgeschobene Teil des Pokes: Arbeitet der Agent gerade (seine Sitzung
# zeigt „esc to interrupt"), tippt BuilderInboxPoke nicht sofort, sondern
# plant diesen Job. Er schaut alle DEFER_RECHECK nach und tippt, sobald die
# Sitzung ruhig ist — auch dann, wenn der Agent nur auf einen Hintergrund-Lauf
# wartet (gemessen: die Anzeige verschwindet dabei).
#
# Er tippt NICHT, wenn sich die Sache erledigt hat:
#  - der Agent hat den Auslöser schon selbst geholt (Heartbeat am Laufende), oder
#  - ein neuerer Poke hat das Flag überschrieben — der hat seinen eigenen Weg.
# Nach DEFER_MAX tippt er trotzdem: Ohne Cron-Rückfall (#441) wäre eine Sitzung,
# die dauerhaft beschäftigt aussieht, sonst für immer taub.
class DeferredInboxPokeJob < ApplicationJob
  queue_as :default

  def perform(actor_id, note, requested_at, geplant_at)
    actor = AgentActor.find_by(id: actor_id)
    return unless actor&.active?
    return unless noch_offen?(actor, requested_at)

    if busy?(actor) && Time.iso8601(geplant_at) > BuilderInboxPoke::DEFER_MAX.ago
      self.class.set(wait: BuilderInboxPoke::DEFER_RECHECK)
                .perform_later(actor_id, note, requested_at, geplant_at)
      return
    end

    tippen(actor, note)
  end

  private

  # Eigene Methoden statt direkter Aufrufe, damit Tests Sitzung und tmux
  # ersetzen können (Unterklasse, wie beim BuilderInboxPoke-Test).
  def busy?(actor)
    BuilderInboxPoke.session_busy?(actor)
  end

  def tippen(actor, note)
    BuilderInboxPoke.tippen(actor, note: note)
  end

  # Offen = das Flag trägt noch genau den Zeitpunkt dieses Pokes UND der
  # Agent war seitdem nicht beim Heartbeat (dieselbe Regel wie `pending_trigger`).
  def noch_offen?(actor, requested_at)
    flag = actor.inbox_run_requested_at
    return false if flag.nil? || flag.iso8601(6) != requested_at
    actor.last_seen_at.nil? || flag > actor.last_seen_at
  end
end
