# #428 Phase 2 (Hans, 2026-05-31): Haelt die zentrale Tag-Registry + die
# taggings synchron mit den tags-Array-Spalten. Single Point of Sync,
# aufgehaengt an after_save von Task / KnowledgeItem (deckt Web-, API- und
# Indexer-/Frontmatter-Schreibpfade ab, weil alle die tags-Spalte aendern).
# Idempotent — auch fuer den einmaligen Backfill nutzbar.
module TagSync
  module_function

  def sync_task(task)
    sync(task.tags, type: "Task", id_int: task.id, uuid: nil)
  end

  def sync_ki(ki)
    sync(ki.tags, type: "KnowledgeItem", id_int: nil, uuid: ki.uuid)
  end

  # #695 (Hans): Kommunikationen taggbar — id-basiert wie Task.
  def sync_communication(comm)
    sync(comm.tags, type: "Communication", id_int: comm.id, uuid: nil)
  end

  def sync(names, type:, id_int:, uuid:)
    desired = Array(names).map { |n| n.to_s.strip.downcase }.reject(&:empty?).uniq
    # uuid-getaggte Typen (KnowledgeItem) über taggable_uuid, id-getaggte
    # (Task, Communication) über taggable_id_int.
    scope =
      if uuid.present?
        Tagging.where(taggable_type: type, taggable_uuid: uuid)
      else
        Tagging.where(taggable_type: type, taggable_id_int: id_int)
      end

    desired_tag_ids = desired.map { |n| Tag.ensure(n).id }
    existing_tag_ids = scope.pluck(:tag_id)

    (desired_tag_ids - existing_tag_ids).each do |tid|
      Tagging.create!(tag_id: tid, taggable_type: type, taggable_id_int: id_int, taggable_uuid: uuid)
    end
    stale = existing_tag_ids - desired_tag_ids
    scope.where(tag_id: stale).delete_all if stale.any?
  end

  # Einmaliger / idempotenter Backfill ueber den Bestand.
  def backfill!
    tasks = kis = 0
    Task.unscoped.where.not(tags: []).find_each { |t| sync_task(t); tasks += 1 }
    KnowledgeItem.where.not(tags: []).find_each { |k| sync_ki(k); kis += 1 }
    { tasks: tasks, kis: kis, tags: Tag.count, taggings: Tagging.count }
  end
end
