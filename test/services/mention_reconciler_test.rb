require "test_helper"

# #378 (Hans, 2026-05-26): Tests fuer MentionReconciler — bringt
# die mentioned_uuid-Spalte einer *_mentions-Association auf den
# gewuenschten Stand (creates+destroys diff).
class MentionReconcilerTest < ActiveSupport::TestCase
  setup do
    @hans = create_human
    grant(@hans, "Task",          %w[read create update delete])
    grant(@hans, "KnowledgeItem", %w[read create update delete])
    @task = Task.create!(title: "T", creator: @hans, assignee: @hans)
  end

  def create_ki(title)
    FileProxy.create(actor: @hans, title: title, item_type: :note, content: "x")
  end

  test "adds missing uuids to the association" do
    with_isolated_miolimos_base do
      a = create_ki("A"); b = create_ki("B")
      MentionReconciler.reconcile!(@task.task_mentions, [a.uuid, b.uuid])
      assert_equal [a.uuid, b.uuid].sort, @task.task_mentions.pluck(:mentioned_uuid).sort
    end
  end

  test "removes uuids that are no longer in the target set" do
    with_isolated_miolimos_base do
      a = create_ki("A"); b = create_ki("B"); c = create_ki("C")
      @task.task_mentions.create!(mentioned_uuid: a.uuid)
      @task.task_mentions.create!(mentioned_uuid: b.uuid)
      MentionReconciler.reconcile!(@task.task_mentions, [a.uuid, c.uuid])
      assert_equal [a.uuid, c.uuid].sort, @task.task_mentions.reload.pluck(:mentioned_uuid).sort
    end
  end

  test "is idempotent — second call with same set is a no-op" do
    with_isolated_miolimos_base do
      a = create_ki("A")
      MentionReconciler.reconcile!(@task.task_mentions, [a.uuid])
      first_ids = @task.task_mentions.pluck(:id).sort
      MentionReconciler.reconcile!(@task.task_mentions, [a.uuid])
      assert_equal first_ids, @task.task_mentions.reload.pluck(:id).sort
    end
  end

  test "exclude_self_uuid filters the self-reference out before reconciling" do
    with_isolated_miolimos_base do
      a = create_ki("A"); self_ki = create_ki("Self")
      MentionReconciler.reconcile!(@task.task_mentions, [a.uuid, self_ki.uuid],
        exclude_self_uuid: self_ki.uuid)
      assert_equal [a.uuid], @task.task_mentions.pluck(:mentioned_uuid)
    end
  end

  test "empty target_uuids removes all existing mentions" do
    with_isolated_miolimos_base do
      a = create_ki("A")
      @task.task_mentions.create!(mentioned_uuid: a.uuid)
      MentionReconciler.reconcile!(@task.task_mentions, [])
      assert_equal [], @task.task_mentions.reload.pluck(:mentioned_uuid)
    end
  end
end
