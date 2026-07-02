require "test_helper"

# #378 Phase 5 (Hans, 2026-05-26): Tests fuer ActorView — die
# View-History (#160). Upsert-Window-Logik ist die Hauptlast.
class ActorViewTest < ActiveSupport::TestCase
  setup do
    @hans = create_human
    grant(@hans, "KnowledgeItem", %w[read create update delete])
    @ki = FileProxy.create(actor: @hans, title: "Notiz", item_type: :note, content: "x")
  end

  test "rejects untracked viewable_type" do
    # Communication ist ein echter Model-Type, aber nicht in TRACKABLE_TYPES.
    av = ActorView.new(actor: @hans, viewable_type: "Communication",
                        viewable_id: 1, viewed_at: Time.current, duration_ms: 0)
    assert_not av.valid?
    assert av.errors[:viewable_type].any?
  end

  test "requires non-negative duration_ms" do
    av = ActorView.new(actor: @hans, viewable_type: "KnowledgeItem",
                        viewable_id: @ki.uuid, viewed_at: Time.current,
                        duration_ms: -1)
    assert_not av.valid?
    assert av.errors[:duration_ms].any?
  end

  test "upsert_for! creates new view when none in window" do
    assert_difference -> { ActorView.count }, 1 do
      ActorView.upsert_for!(actor: @hans, viewable_type: "KnowledgeItem",
                             viewable_id: @ki.uuid, duration_ms: 100)
    end
  end

  test "upsert_for! merges into existing view within window" do
    first = ActorView.upsert_for!(actor: @hans, viewable_type: "KnowledgeItem",
                                    viewable_id: @ki.uuid, duration_ms: 100)
    assert_no_difference -> { ActorView.count } do
      ActorView.upsert_for!(actor: @hans, viewable_type: "KnowledgeItem",
                             viewable_id: @ki.uuid, duration_ms: 50)
    end
    first.reload
    assert_equal 100, first.duration_ms, "should keep max duration"
  end

  test "upsert_for! takes max duration on merge" do
    ActorView.upsert_for!(actor: @hans, viewable_type: "KnowledgeItem",
                           viewable_id: @ki.uuid, duration_ms: 50)
    ActorView.upsert_for!(actor: @hans, viewable_type: "KnowledgeItem",
                           viewable_id: @ki.uuid, duration_ms: 999)
    av = ActorView.where(viewable_type: "KnowledgeItem",
                          viewable_id: @ki.uuid).first
    assert_equal 999, av.duration_ms
  end

  test "upsert_for! OR-merges was_edited flag" do
    ActorView.upsert_for!(actor: @hans, viewable_type: "KnowledgeItem",
                           viewable_id: @ki.uuid, duration_ms: 50, was_edited: false)
    ActorView.upsert_for!(actor: @hans, viewable_type: "KnowledgeItem",
                           viewable_id: @ki.uuid, duration_ms: 100, was_edited: true)
    av = ActorView.where(viewable_type: "KnowledgeItem",
                          viewable_id: @ki.uuid).first
    assert av.was_edited
  end

  test "upsert_for! creates new row past dedupe window" do
    travel_to(2.minutes.ago) do
      ActorView.upsert_for!(actor: @hans, viewable_type: "KnowledgeItem",
                             viewable_id: @ki.uuid, duration_ms: 50)
    end
    assert_difference -> { ActorView.count }, 1 do
      ActorView.upsert_for!(actor: @hans, viewable_type: "KnowledgeItem",
                             viewable_id: @ki.uuid, duration_ms: 50)
    end
  end

  test "for_actor scope filters by actor" do
    other = create_human(email: "other-#{SecureRandom.hex(3)}@t.local")
    ActorView.upsert_for!(actor: @hans, viewable_type: "KnowledgeItem",
                           viewable_id: @ki.uuid, duration_ms: 10)
    ActorView.upsert_for!(actor: other, viewable_type: "KnowledgeItem",
                           viewable_id: @ki.uuid, duration_ms: 10)
    assert_equal 1, ActorView.for_actor(@hans).count
  end

  test "distinct_recent returns one row per (type, id)" do
    travel_to(3.minutes.ago) do
      ActorView.upsert_for!(actor: @hans, viewable_type: "KnowledgeItem",
                             viewable_id: @ki.uuid, duration_ms: 10)
    end
    ActorView.upsert_for!(actor: @hans, viewable_type: "KnowledgeItem",
                           viewable_id: @ki.uuid, duration_ms: 10)
    assert_equal 1, ActorView.distinct_recent.where(viewable_type: "KnowledgeItem",
                                                      viewable_id: @ki.uuid).count
  end
end
