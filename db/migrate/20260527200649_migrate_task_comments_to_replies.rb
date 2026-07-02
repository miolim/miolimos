# #384 Phase 3c (Hans, 2026-05-27): Bestehende `task_comments` werden
# zu Reply-KIs (item_type=:reply, parent_type="Task",
# parent_id_int=task_id). Direkt-Cutover pro Hans-Spec, kein dual-
# write. task_comments-Tabelle bleibt zunaechst stehen (read-only-
# Archiv); spaeter via separater Migration dropbar.
#
# Idempotent: existieren bereits Reply-KIs mit parent_type="Task" und
# parent_id_int=<tc.task_id> + created_at gleich der TaskComment-
# Stempel + creator_id gleich actor_id, ueberspringt der Loop.
class MigrateTaskCommentsToReplies < ActiveRecord::Migration[8.1]
  def up
    return unless ActiveRecord::Base.connection.table_exists?("task_comments")
    reply_enum = KnowledgeItem.item_types[:reply]
    migrated  = 0
    skipped   = 0
    TaskComment.find_each do |tc|
      already = KnowledgeItem.where(
        item_type:     reply_enum,
        parent_type:   "Task",
        parent_id_int: tc.task_id,
        creator_id:    tc.actor_id,
        created_at:    tc.created_at
      ).exists?
      if already
        skipped += 1
        next
      end
      KnowledgeItem.create!(
        uuid:           SecureRandom.uuid,
        item_type:      :reply,
        title:          nil,
        body:           tc.body.to_s,
        creator_id:     tc.actor_id,
        parent_type:    "Task",
        parent_id_int:  tc.task_id,
        published_at:   tc.published_at,
        created_at:     tc.created_at,
        updated_at:     tc.updated_at,
        file_path:      "knowledge/replies/migrated-tc-#{tc.id}.md",
        content_hash:   Digest::SHA256.hexdigest(tc.body.to_s),
        file_created_at: tc.created_at,
        file_updated_at: tc.updated_at,
        indexed_at:     Time.current
      )
      migrated += 1
    rescue ActiveRecord::RecordInvalid => e
      Rails.logger.warn "TaskComment ##{tc.id} migration skipped: #{e.message}"
      skipped += 1
    end
    Rails.logger.info "TaskComment migration: #{migrated} migrated, #{skipped} skipped"
    say "TaskComment migration: #{migrated} migrated, #{skipped} skipped"
  end

  def down
    # Loescht alle Replies, die als TaskComment-Migration angelegt
    # wurden (file_path-Praefix `knowledge/replies/migrated-tc-`).
    KnowledgeItem.replies
                 .where("file_path LIKE ?", "knowledge/replies/migrated-tc-%")
                 .destroy_all
  end
end
