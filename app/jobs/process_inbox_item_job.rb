# Async-Wrapper um Inbox::ProcessorBase. Sorgt dafür, dass langlaufende
# Processors (Whisper, Anthropic-Calls, yt-dlp-Downloads) nicht den
# HTTP-Request blockieren. Status-Übergänge übernimmt nach wie vor die
# ProcessorBase — der Job ist nur Dispatcher.
#
# Solid Queue speichert Jobs persistent in der queue-DB; ein
# Service-Restart unterbricht laufende Jobs zwar, lässt aber unprocessed
# Jobs in der Queue stehen, sodass sie nach dem Restart fortgesetzt
# werden.
class ProcessInboxItemJob < ApplicationJob
  queue_as :default

  # Beim Deserialisieren: Item könnte gelöscht worden sein zwischen
  # Enqueue und Pickup. Dann verwerfen statt failed.
  discard_on ActiveJob::DeserializationError

  # #1675: Der Controller setzt den Eintrag schon VOR dem Einreihen auf
  # „processing". Kehrt der Job dann still zurück oder wirft, bevor ein
  # Prozessor den Status übernimmt, bleibt der Eintrag für immer dort — die
  # Ansicht zeigt dann nur noch den Warte-Kreisel. Deshalb endet jeder dieser
  # Ausgänge SICHTBAR als „failed" mit Grund; von dort lässt er sich neu starten.
  def perform(inbox_item_id, processor_kind, actor_id)
    item = InboxItem.find_by(id: inbox_item_id)
    return unless item   # gelöscht zwischen Einreihen und Abholen

    actor = Actor.find_by(id: actor_id)
    return abbrechen(item, "Der auslösende Nutzer (##{actor_id}) existiert nicht mehr.") unless actor

    klass = Inbox::Registry.find(processor_kind)
    return abbrechen(item, "Unbekannter Prozessor: #{processor_kind}") unless klass

    klass.run(item, actor: actor)
  end

  private

  def abbrechen(item, grund)
    Rails.logger.error("ProcessInboxItemJob(item=#{item.id}): #{grund}")
    item.update_columns(status: "failed", error_message: grund, updated_at: Time.current)
  end
end
