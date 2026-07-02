# #480 Increment 3 (Hans, 2026-06-03): Synct die `task_anchors`-Tabelle fuer
# eine Aufgabe — extrahiert alle Anker (Highlight + nackte Block-Anker) aus
# der Description und gleicht den DB-Stand ab. Pendant zu
# KnowledgeMarkdown::Anchors.sync_for (KI-Body); nutzt denselben Extractor,
# damit Anker-Erkennung „ueberall gleich" ist. Aufruf: Task-after_save bei
# Description-Aenderung.
module TaskAnchors
  module Sync
    extend self

    def call(task)
      return unless task&.persisted?

      desired  = KnowledgeMarkdown::Anchors.extract(task.description.to_s).keys
      existing = TaskAnchor.where(task_id: task.id)
      current  = existing.pluck(:anchor)

      (current - desired).each { |obsolete| existing.where(anchor: obsolete).delete_all }

      (desired - current).each do |anchor|
        TaskAnchor.create!(task_id: task.id, anchor: anchor)
      rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
        # Anker schon woanders vergeben (KI oder andere Task) — Kollision.
        # SecureRandom macht das praktisch unmoeglich; falls doch, schweigen
        # wir (Wikilink zeigt auf den aelteren Owner), statt den Task-Save
        # zu sprengen. Analog zu KnowledgeMarkdown::Anchors.sync_for (#466).
        next
      end
    end
  end
end
