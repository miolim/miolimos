require "test_helper"

# #1109: Topbar-Layout-Vorliebe pro Actor (ActorPreferences) — gleiches
# Muster wie das Sidebar-Layout (#846, actor_sidebar_layout_test.rb).
class ActorTopbarLayoutTest < ActiveSupport::TestCase
  def actor
    @actor ||= HumanActor.create!(name: "T", email: "tb-#{SecureRandom.hex(3)}@t.local")
  end

  test "default layout matches TOPBAR_ITEM_DEFAULTS and covers every item" do
    layout = actor.pref_topbar_layout
    assert_equal %w[quick_task quick_awaiting quick_ki quick_person quick_inbox timer], layout["left"]
    assert_equal %w[theme shortcuts inspector diagnostic], layout["right"]
    assert_empty layout["hidden"]
    all = layout.values.flatten
    assert_equal ActorPreferences::TOPBAR_ITEM_IDS.sort, all.sort
    assert_equal all.uniq, all, "keine ID doppelt"
  end

  test "saved layout is honored, order preserved" do
    actor.update_preferences(
      "topbar_layout" => { "left" => "timer,quick_task", "right" => "diagnostic", "hidden" => "inspector" }
    )
    layout = actor.pref_topbar_layout
    assert_equal %w[timer quick_task], layout["left"].first(2)
    assert_equal ["inspector"], layout["hidden"], "hidden bekommt keine Auto-Ergaenzung"
  end

  test "missing (newly added) ids are appended to their default section, visible" do
    actor.update_preferences(
      "topbar_layout" => { "left" => "quick_task", "right" => "theme", "hidden" => "" }
    )
    layout = actor.pref_topbar_layout
    all = layout.values.flatten
    assert_includes all, "diagnostic", "fehlende ID wird ergaenzt"
    assert_includes layout["right"], "diagnostic", "und zwar sichtbar an ihrem Default-Platz"
    refute_includes layout["hidden"], "diagnostic"
    assert_equal ActorPreferences::TOPBAR_ITEM_IDS.sort, all.sort
  end

  test "unknown ids are dropped and duplicates deduped across sections" do
    actor.update_preferences(
      "topbar_layout" => { "left" => "quick_task,bogus", "right" => "quick_task,theme", "hidden" => "" }
    )
    raw = actor.preferences["topbar_layout"]
    refute_includes raw.values.flatten, "bogus"
    assert_includes raw["left"], "quick_task"
    refute_includes raw["right"], "quick_task"
  end

  test "layout accepts array input (not only comma strings)" do
    actor.update_preferences(
      "topbar_layout" => { "left" => %w[quick_inbox quick_task], "right" => %w[theme], "hidden" => [] }
    )
    assert_equal %w[quick_inbox quick_task], actor.pref_topbar_layout["left"].first(2)
  end
end
