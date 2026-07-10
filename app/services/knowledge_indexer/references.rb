# #203 Phase E.9: Wikilink-/Reference-Logik aus KnowledgeIndexer
# extrahiert. Drei Public-Entry-Points werden von FileProxy::Writer
# direkt gerufen (NICHT via KnowledgeIndexer.run-Pfad).
class KnowledgeIndexer
  module References
    WIKILINK_REGEX = /\[\[([^\]|#\^]+)(?:#([^\]|]+))?(?:\^([^\]|]+))?(?:\|[^\]]+)?\]\]/
    UUID_RE        = /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i

    module_function

    # Body scannen, outgoing_references neu schreiben. KEINE Title-Aufloesung
    # — die uebernimmt rebuild_all am Ende eines vollen Indexer-Laufs. Wird
    # vom internen Indexer-Pfad benutzt.
    # #475 (Hans, 2026-06-02): Erkennt eine Anker-only-Referenz
    # (`[[^id]]`) — Ziel wird ueber KnowledgeItemAnchor (anchor -> KI)
    # statt ueber den Titel aufgeloest. Signatur: anchor_type=block und
    # target_title == anchor_text (beide = die 6/8-stellige Anker-ID).
    def anchor_only_ref?(ref)
      ref.anchor_type.to_s == "block" &&
        ref.target_title.to_s == ref.anchor_text.to_s &&
        ref.target_title.to_s.match?(/\A[a-z0-9]{6,8}\z/)
    end

    def insert_from_body(item, body)
      item.outgoing_references.destroy_all
      # #475 (Hans, 2026-06-02): Anker-only `[[^id]]`-Links erzeugen
      # ebenfalls eine Referenz (Ziel via KnowledgeItemAnchor). Erst
      # dadurch werden Backlinks auf Antwort-Absaetze ueberhaupt erfasst —
      # Replies haben keinen Titel, sind also nur per `[[^id]]` verlinkbar,
      # und WIKILINK_REGEX schliesst `^`-Praefix-Links aus.
      body.to_s.scan(KnowledgeMarkdown::Wikilinks::ANCHOR_ONLY_RE) do |anchor, _alias|
        row = KnowledgeItemAnchor.find_by(anchor: anchor)
        item.outgoing_references.create!(
          target_title: anchor,
          target_uuid:  row&.knowledge_item_uuid,
          anchor_type:  :block,
          anchor_text:  anchor
        )
      end
      # #953: Aufgaben-Referenzen `[[#id]]` — Ziel ist eine Task, nicht
      # eine KI (target_task_id statt target_uuid). WIKILINK_REGEX
      # schliesst `#`-Praefix-Links aus, kein Doppel-Erfassen. Nicht
      # existierende Task-IDs werden nicht erfasst (kaputter Link braucht
      # keinen Alarm, analog #241).
      body.to_s.scan(KnowledgeMarkdown::Wikilinks::TASK_REF_RE) do |task_id, _alias|
        next unless Task.exists?(id: task_id)
        item.outgoing_references.create!(
          target_title:   "##{task_id}",
          target_task_id: task_id,
          anchor_type:    :file
        )
      end
      body.to_s.scan(WIKILINK_REGEX) do |target_id, heading, block|
        anchor_type, anchor_text =
          if block
            [:block, block.to_s.strip]
          elsif heading
            [:heading, heading.to_s.strip]
          else
            [:file, nil]
          end

        target_id = target_id.to_s.strip
        if target_id =~ UUID_RE
          # UUID-Form: Target-UUID direkt setzen, target_title bleibt fuer
          # Anzeige-Zwecke der UUID-String.
          # #241 (2026-05-19): Wenn die Target-UUID nicht in
          # knowledge_items existiert (z.B. kaputter Link auf eine
          # geloeschte Notiz), als dangling-Ref ohne target_uuid
          # speichern. Hans-Spec: "kaputter Link braucht keinen Alarm,
          # der fliegt dann raus."
          if KnowledgeItem.with_discarded.where(uuid: target_id.downcase).exists?
            item.outgoing_references.create!(
              target_title: target_id,
              target_uuid:  target_id.downcase,
              anchor_type:  anchor_type,
              anchor_text:  anchor_text
            )
          else
            item.outgoing_references.create!(
              target_title: target_id,
              target_uuid:  nil,
              anchor_type:  anchor_type,
              anchor_text:  anchor_text
            )
          end
        else
          item.outgoing_references.create!(
            target_title: target_id,
            target_uuid:  nil,
            anchor_type:  anchor_type,
            anchor_text:  anchor_text
          )
        end
      end
    end

    # Wird von FileProxy.create/update aufgerufen, damit Wikilinks im
    # Body sofort als KnowledgeItemReference in der DB landen — ohne
    # auf den naechsten Indexer-Lauf zu warten. Macht insert + die
    # Title-Aufloesung fuer die outgoing-Refs dieses Items in einem
    # Aufruf.
    def index_body_references_for(item, body)
      # #663: Block-Anker-Ziele VOR dem Neuschreiben merken, um auch
      # entfernte Rückverweise zu erfassen (Quelle editiert/Link raus).
      old_block_targets = item.outgoing_references
                              .where(anchor_type: :block).where.not(target_uuid: nil)
                              .pluck(:target_uuid)
      insert_from_body(item, body)
      # #953: Task-Refs sind bereits final (target_task_id) — nicht als
      # KI-Titel aufzuloesen versuchen.
      item.outgoing_references.where(target_uuid: nil, target_task_id: nil).find_each do |ref|
        next if ref.target_title =~ UUID_RE
        if anchor_only_ref?(ref)
          # #475: noch nicht indizierter Anker -> spaeter via
          # KnowledgeItemAnchor aufloesen (z.B. wenn der Ziel-Absatz erst
          # nach dieser Quelle gespeichert wird).
          row = KnowledgeItemAnchor.find_by(anchor: ref.anchor_text)
          ref.update!(target_uuid: row.knowledge_item_uuid) if row
        else
          target = KnowledgeItem.by_title_ci(ref.target_title).first
          ref.update!(target_uuid: target.uuid) if target
        end
      end

      # #663: Render-Cache aller (alten + neuen) Block-Anker-Ziele
      # verwerfen — ihre markierten Stellen müssen den Backlink-Indikator
      # auf dieses Item neu rendern. Sich selbst nicht (eigenes updated_at
      # bustet ohnehin).
      new_block_targets = current_block_anchor_targets(item)
      bust_render_caches((old_block_targets + new_block_targets).uniq - [item.uuid])
    end

    # #953 Folge (Hans): auch Task-BESCHREIBUNGEN sind Referenz-Quellen —
    # Aufgaben- ([[#id]]) wie KI-Links ([[Titel]], [[uuid]], [[^anker]])
    # landen mit source_task_id im Index. Aufgerufen von Task#save bei
    # geänderter Beschreibung und vom Backfill. Titel werden sofort
    # aufgelöst; dangling Refs zieht resolve_dangling_references_to /
    # rebuild_all später nach (gleiche Semantik wie KI-Bodies).
    def index_task_description_references(task)
      old_block_targets = KnowledgeItemReference
                            .where(source_task_id: task.id, anchor_type: :block)
                            .where.not(target_uuid: nil).pluck(:target_uuid)
      KnowledgeItemReference.where(source_task_id: task.id).delete_all
      body = task.description.to_s

      body.scan(KnowledgeMarkdown::Wikilinks::ANCHOR_ONLY_RE) do |anchor, _alias|
        row = KnowledgeItemAnchor.find_by(anchor: anchor)
        KnowledgeItemReference.create!(
          source_task_id: task.id, target_title: anchor,
          target_uuid: row&.knowledge_item_uuid, anchor_type: :block, anchor_text: anchor)
      end
      body.scan(KnowledgeMarkdown::Wikilinks::TASK_REF_RE) do |task_id, _alias|
        next if task_id.to_i == task.id  # Selbstverweis ist kein Backlink
        next unless Task.exists?(id: task_id)
        KnowledgeItemReference.create!(
          source_task_id: task.id, target_title: "##{task_id}",
          target_task_id: task_id, anchor_type: :file)
      end
      body.scan(WIKILINK_REGEX) do |target_id, heading, block|
        anchor_type, anchor_text =
          if block then [:block, block.to_s.strip]
          elsif heading then [:heading, heading.to_s.strip]
          else [:file, nil]
          end
        target_id = target_id.to_s.strip
        target_uuid =
          if target_id =~ UUID_RE
            target_id.downcase if KnowledgeItem.with_discarded.where(uuid: target_id.downcase).exists?
          else
            KnowledgeItem.by_title_ci(target_id).first&.uuid
          end
        KnowledgeItemReference.create!(
          source_task_id: task.id, target_title: target_id,
          target_uuid: target_uuid, anchor_type: anchor_type, anchor_text: anchor_text)
      end

      new_block_targets = KnowledgeItemReference
                            .where(source_task_id: task.id, anchor_type: :block)
                            .where.not(target_uuid: nil).pluck(:target_uuid)
      bust_render_caches((old_block_targets + new_block_targets).uniq)
    end

    # #663: aktuelle Block-Anker-Ziele eines Items (mit aufgelöster UUID).
    def current_block_anchor_targets(item)
      item.outgoing_references
          .where(anchor_type: :block).where.not(target_uuid: nil)
          .pluck(:target_uuid)
    end

    # #663: Render-Caches der gegebenen Ziel-UUIDs verwerfen (Backlink-
    # Indikatoren). Auch von Trash/Restore genutzt.
    def bust_render_caches(target_uuids)
      Array(target_uuids).uniq.each do |tuuid|
        KnowledgeMarkdown.bust_cache(KnowledgeItem.find_by(uuid: tuuid))
      end
    end

    # Wenn ein KI angelegt oder umbenannt wird, kann es bereits Refs aus
    # frueheren Bodies geben, die per Title auf diesen Namen zeigen, aber
    # noch nil als target_uuid stehen haben. Diese Refs jetzt retroaktiv
    # aufloesen.
    def resolve_dangling_references_to(title, target_uuid)
      return if title.blank? || target_uuid.blank?
      KnowledgeItemReference
        .where(target_uuid: nil, target_task_id: nil)  # #953: Task-Refs nie umbiegen
        .where("lower(target_title) = ?", title.to_s.downcase)
        .update_all(target_uuid: target_uuid)
    end

    # Person-Frontmatter `parent_org:` darf UUID ODER Title sein —
    # diese Methode loest beides auf eine uuid auf.
    def resolve_parent_org_uuid(value)
      return nil if value.blank?
      s = value.to_s.strip
      return s.downcase if s =~ UUID_RE
      KnowledgeItem.by_title_ci(s).first&.uuid
    end

    # Voll-Reindex: re-evaluates target_uuid for every reference row.
    # O(references) pro Reindex-Lauf, was billig ist; die Alternative
    # (Title-Changes ueber Rename-Events tracken) ist deutlich komplexer.
    #
    #   nil → uuid   (target now exists with that title)
    #   uuid → nil   (target was renamed or deleted)
    #   uuid → uuid' (target title is now owned by a different item)
    def rebuild_all
      title_to_uuid = KnowledgeItem.pluck(:title, :uuid).to_h { |t, u| [t.downcase, u] }

      KnowledgeItemReference.find_each do |ref|
        next if ref.target_task_id.present?  # #953: Task-Refs sind final
        next if ref.target_title =~ UUID_RE
        # #475: Anker-only-Refs ueber KnowledgeItemAnchor statt Titel.
        expected =
          if anchor_only_ref?(ref)
            KnowledgeItemAnchor.find_by(anchor: ref.anchor_text)&.knowledge_item_uuid
          else
            title_to_uuid[ref.target_title.downcase]
          end
        ref.update!(target_uuid: expected) if ref.target_uuid != expected
      end

      KnowledgeItemReference.where.not(target_uuid: nil).count
    end
  end
end
