module Inbox
  # Abstract base. Konkrete Processors implementieren `process!` und
  # melden Erzeugnisse via `record_result`. Status-Übergänge übernimmt
  # die Base-Klasse.
  #
  # Subklassen müssen implementieren:
  #   - kind          (String, eindeutig — landet in inbox_item.processor_kind)
  #   - applies?(item) → Boolean
  #   - process!(item, actor:) → void  (raise bei Fehler)
  class ProcessorBase
    # Soft-Pause: Processor erkennt einen Punkt, an dem User-Bestätigung
    # nötig ist (z.B. Whisper-Kosten bei langen YT-Videos). Item landet in
    # awaiting_confirmation, UI zeigt einen Banner mit Detail-Info aus
    # `details`. Ein Re-Run mit `confirm_*=true` im payload überspringt
    # den Check.
    class NeedsConfirmation < StandardError
      attr_reader :details
      def initialize(details = {})
        @details = details
        super(details[:reason].to_s.presence || "needs_confirmation")
      end
    end
    class << self
      def kind         = raise NotImplementedError
      def label        = kind.humanize
      def description  = ""
      def applies?(_item) = false
    end

    def self.run(item, actor:)
      item.update!(
        status:        "processing",
        processor_kind: kind,
        error_message: nil
      )
      new.process!(item, actor: actor)
      item.update!(status: "processed", processed_at: Time.current)
      true
    rescue ProcessorBase::NeedsConfirmation => e
      item.update!(
        status: "awaiting_confirmation",
        result: item.result.merge("confirmation" => e.details.stringify_keys)
      )
      false
    rescue => e
      Rails.logger.warn("Inbox::#{kind}: #{e.class} #{e.message}\n#{e.backtrace.first(5).join("\n")}")
      item.update!(
        status:        "failed",
        error_message: "#{e.class}: #{e.message.truncate(500)}"
      )
      false
    end

    # Subklassen helfen-call: ein KI in `result` registrieren und mit
    # InboxItem verlinken. Beim KI wird zusätzlich die Inbox-Provenance
    # ins Frontmatter geschrieben — rein dokumentarisch, der Indexer
    # liest's nicht zurück (DB-Spalte inbox_item_id bleibt Wahrheit).
    def record_result(item, knowledge_item: nil, task: nil)
      list = Array(item.result["created"])
      if knowledge_item
        knowledge_item.update_column(:inbox_item_id, item.id)
        inherit_topics_to_ki(knowledge_item, item)
        list << { "kind" => "knowledge_item", "uuid" => knowledge_item.uuid, "title" => knowledge_item.title }
        write_inbox_provenance(knowledge_item, item)
      end
      if task
        task.update_column(:inbox_item_id, item.id)
        inherit_topics_to_task(task, item)
        list << { "kind" => "task", "id" => task.id, "title" => task.title }
      end
      item.update_column(:result, item.result.merge("created" => list))
    end

    private

    # #171: Auf dem InboxItem vorgepflegte Themen werden auf das erzeugte
    # KI/Task mit-übernommen. Idempotent — find_or_create_by sorgt dafür,
    # dass ein durch den LLM-Klassifikator schon angehängtes Topic nicht
    # doppelt verlinkt wird. Hans wollte explizit, dass der Klassifikator
    # NICHT auf die vorgepflegten Themen draufergänzt — das verbieten wir
    # auf Processor-Ebene allerdings nicht. Wenn der LLM-Pfad das tut,
    # gilt das hier additiv. Echte Begrenzung kommt in den Processoren,
    # die heute schon Topics setzen (z.B. markdown_to_ki via fm["topics"]).
    def inherit_topics_to_ki(knowledge_item, inbox_item)
      inbox_item.topics.each do |topic|
        KnowledgeItemTopic.find_or_create_by!(
          knowledge_item_uuid: knowledge_item.uuid, topic_id: topic.id
        )
      end
    rescue => e
      Rails.logger.warn("ProcessorBase: inherit_topics_to_ki fehlgeschlagen für #{knowledge_item.uuid}: #{e.class} #{e.message}")
    end

    def inherit_topics_to_task(task, inbox_item)
      inbox_item.topics.each do |topic|
        position = (topic.task_topics.maximum(:position) || 0) + 1
        TaskTopic.find_or_create_by!(task: task, topic: topic) do |link|
          link.position = position
        end
      end
    rescue => e
      Rails.logger.warn("ProcessorBase: inherit_topics_to_task fehlgeschlagen für #{task.id}: #{e.class} #{e.message}")
    end

    def write_inbox_provenance(knowledge_item, inbox_item)
      provenance = {
        "origin"     => "inbox",
        "source_url" => inbox_item.source_url.presence,
        "title"      => inbox_item.title.presence,
        "kind"       => inbox_item.source_kind
      }.compact
      # #241 Plan B: Provenance lebt jetzt in der DB-Spalte
      # `knowledge_items.provenance` (jsonb), nicht mehr im
      # File-Frontmatter. Reader rekonstruiert sie wieder ins YAML
      # zur Anzeige.
      knowledge_item.update!(provenance: provenance)
    rescue => e
      Rails.logger.warn("ProcessorBase: write_inbox_provenance fehlgeschlagen für #{knowledge_item.uuid}: #{e.class} #{e.message}")
    end

    def kind = self.class.kind
  end
end
