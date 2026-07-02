class FileProxy
  # Soft-Delete, Restore und Purge fuer Knowledge-Items.
  module Trash
    extend self

    # Soft-Delete: KI-Record bekommt deleted_at, Datei wandert in
    # knowledge/.trash/<rel_path>. Git-Commit dokumentiert die
    # Verschiebung. Restore ist Inverse — Datei zurueck, deleted_at = nil.
    def destroy(actor:, knowledge_item:)
      rel_path  = knowledge_item.file_path
      full_path = BASE_PATH.join(rel_path) if rel_path.present?

      # #663: Die Stellen, die dieses KI rückverlinkt hat, verlieren ihren
      # Backlink-Indikator — ihren Render-Cache verwerfen.
      KnowledgeIndexer::References.bust_render_caches(
        KnowledgeIndexer::References.current_block_anchor_targets(knowledge_item)
      )
      knowledge_item.discard!

      if full_path && File.exist?(full_path)
        trash_rel  = File.join("knowledge", ".trash", rel_path.sub(%r{\Aknowledge/}, ""))
        trash_full = BASE_PATH.join(trash_rel)
        FileUtils.mkdir_p(File.dirname(trash_full))
        FileUtils.mv(full_path, trash_full)
        GitRepo.commit(actor: actor, file_path: [rel_path, trash_rel],
                       message: "Trash: #{knowledge_item.title}")
      end
    end

    def restore(actor:, knowledge_item:)
      rel_path = knowledge_item.file_path
      return unless rel_path.present?

      trash_rel  = File.join("knowledge", ".trash", rel_path.sub(%r{\Aknowledge/}, ""))
      trash_full = BASE_PATH.join(trash_rel)
      full_path  = BASE_PATH.join(rel_path)

      if File.exist?(trash_full)
        FileUtils.mkdir_p(File.dirname(full_path))
        FileUtils.mv(trash_full, full_path)
        GitRepo.commit(actor: actor, file_path: [trash_rel, rel_path],
                       message: "Restore: #{knowledge_item.title}")
      end

      knowledge_item.undiscard!
      # #663: Rückverweise sind wieder gültig — Ziel-Caches verwerfen.
      KnowledgeIndexer::References.bust_render_caches(
        KnowledgeIndexer::References.current_block_anchor_targets(knowledge_item)
      )
    end

    # Endgueltig loeschen — Cron raeumt nach 30 Tagen damit auf.
    def purge!(actor:, knowledge_item:)
      rel_path  = knowledge_item.file_path
      trash_rel = File.join("knowledge", ".trash", rel_path.sub(%r{\Aknowledge/}, "")) if rel_path
      trash_full = BASE_PATH.join(trash_rel) if trash_rel

      KnowledgeItem.with_discarded.find(knowledge_item.uuid).destroy

      if trash_full && File.exist?(trash_full)
        File.delete(trash_full)
        GitRepo.commit(actor: actor, file_path: trash_rel,
                       message: "Purged: #{knowledge_item.title}")
      end
    end
  end
end
