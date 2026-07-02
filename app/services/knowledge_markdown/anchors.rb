class KnowledgeMarkdown
  # #387 Phase A.3 (Hans, 2026-05-28): Indexiert die 8-Hex-Anker, die
  # an Color-Highlight-Wraps (`==color|text==^id`) im Body haengen.
  # Befuellt eine Lookup-Tabelle, sodass `[[^id]]`-Wikilinks
  # global aufgeloest werden koennen (Anker → KI-UUID).
  module Anchors
    extend self

    # #387 Phase B (Hans, 2026-05-30): Optionaler Tag-Suffix
    # `#tag1#tag2` direkt nach dem 8-Hex-Anker.
    ANCHOR_IN_BODY_RE = /==(?:[a-z]+)\|[^=]{1,4000}?==\^([a-f0-9]{8}|[a-z0-9]{6})((?:#[a-zA-Z0-9_-]+)*)/m.freeze

    # Liefert Hash {anchor => Array<tag>}. Wenn ein Anker mehrfach im
    # selben Body steht (sollte nicht passieren), gewinnt die letzte
    # Variante mit ihren Tags.
    def extract(body)
      result = {}
      body.to_s.scan(ANCHOR_IN_BODY_RE).each do |anchor, tag_blob|
        tags = tag_blob.to_s.split("#").reject(&:blank?).map { |t| t.strip.downcase }
        result[anchor] = tags
      end
      # #466 (Hans, 2026-06-02): nackte Block-Anker (`…absatz ^id` am
      # Zeilenende, von ensure_anchor) indizieren — damit `[[^id]]` global
      # aufloest, auch fuer Absaetze in Antworten. Nach der Anker-
      # Vereinheitlichung erzeugt ensure_anchor 8-stellig Hex; aeltere
      # Anker sind 6-stellig alphanumerisch — beide erfassen. Keine Tags.
      # Highlight-Anker (`==…==^8hex`) sind vom `==` statt `[ \t]` praefixt
      # → kein Doppel, werden ueber ANCHOR_IN_BODY_RE erfasst.
      body.to_s.scan(/[ \t]\^([a-f0-9]{8}|[a-z0-9]{6})[ \t]*$/).each do |(anchor)|
        result[anchor] ||= []
      end
      result
    end

    # Synct die `knowledge_item_anchors`-Tabelle fuer ein KI: extrahiert
    # alle Anker + Tags aus dem aktuellen Body und gleicht den DB-Stand
    # ab. Aufruf-Stelle: nach jedem KI-Save in FileProxy::Writer.
    def sync_for(item, body)
      return unless item&.persisted?
      desired = extract(body)
      existing = KnowledgeItemAnchor.where(knowledge_item_uuid: item.uuid)
      existing_records = existing.index_by(&:anchor)

      (existing_records.keys - desired.keys).each do |obsolete|
        existing.where(anchor: obsolete).delete_all
      end

      desired.each do |anchor, tags|
        if (record = existing_records[anchor])
          record.update!(tags: tags) if record.tags.to_a.sort != tags.sort
        else
          KnowledgeItemAnchor.create!(knowledge_item_uuid: item.uuid, anchor: anchor, tags: tags)
        end
      rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
        # Anker schon in ANDEREM KI vergeben — Kollision. Die Uniqueness-
        # VALIDIERUNG wirft RecordInvalid (nicht RecordNotUnique, das nur
        # bei umgangener Validierung am DB-Constraint feuert) — #466
        # (Hans, 2026-06-02): beide fangen, sonst BRICHT der KI-Save (500),
        # sobald ein Body einen bereits anderswo vergebenen Anker enthaelt.
        # SecureRandom ist eindeutig genug, dass das praktisch nicht
        # passiert; falls doch, schweigen wir (der Anker bleibt im File,
        # der Wikilink zeigt aufs aeltere KI). Cleanup-Job spaeter.
        next
      end
    end
  end
end
