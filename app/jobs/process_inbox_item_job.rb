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

  def perform(inbox_item_id, processor_kind, actor_id)
    item  = InboxItem.find_by(id: inbox_item_id)
    actor = Actor.find_by(id: actor_id)
    return unless item && actor

    klass = Inbox::Registry.find(processor_kind)
    raise "Unknown processor: #{processor_kind.inspect}" unless klass

    klass.run(item, actor: actor)
  end
end
