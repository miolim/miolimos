require "test_helper"

# #1055 (Lücke): Die Prune-Logik (trim! → delete_all) hatte keine direkte
# Absicherung. Ein Off-by-one im keep-Set würde still Verlauf löschen —
# gepinnte Snapshots dürfen NIE getrimmt werden, aktuelle Recent-Einträge
# nur jenseits von MAX_RECENT.
class StackSnapshotTrimTest < ActiveSupport::TestCase
  setup do
    @actor = create_human
    @key   = "stack.history.list:tasks"
  end

  def record!(n, pinned: false, at: Time.current)
    travel_to(at) do
      StackSnapshot.record!(actor: @actor, history_key: @key,
                            trail: [["list:tasks", "task:#{n}"]], current: 0, pinned: pinned)
    end
  end

  test "trimmt unpinned auf MAX_RECENT, die jüngsten überleben" do
    (StackSnapshot::MAX_RECENT + 3).times { |i| record!(i, at: i.minutes.ago) }
    bucket = StackSnapshot.for_bucket(@actor, @key)
    assert_equal StackSnapshot::MAX_RECENT, bucket.count
    # die jüngsten (kleinste minutes.ago) sind drin, die ältesten drei raus
    survivors = bucket.pluck(:dedup_key)
    assert_includes survivors, "list:tasks,task:0"
    assert_not_includes survivors, "list:tasks,task:#{StackSnapshot::MAX_RECENT + 2}"
  end

  test "gepinnte Snapshots überleben das Trimmen immer" do
    pinned = record!(999, pinned: true, at: 2.days.ago)
    (StackSnapshot::MAX_RECENT + 2).times { |i| record!(i, at: i.minutes.ago) }
    assert StackSnapshot.exists?(pinned.id), "gepinnter Snapshot wurde getrimmt"
    assert_equal StackSnapshot::MAX_RECENT + 1, StackSnapshot.for_bucket(@actor, @key).count
  end

  test "Trimmen bleibt im Bucket — andere history_keys unberührt" do
    other = StackSnapshot.record!(actor: @actor, history_key: "stack.history.list:documents",
                                  trail: [["list:documents"]], current: 0)
    (StackSnapshot::MAX_RECENT + 2).times { |i| record!(i, at: i.minutes.ago) }
    assert StackSnapshot.exists?(other.id)
  end
end
