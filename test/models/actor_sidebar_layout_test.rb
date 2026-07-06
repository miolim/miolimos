require "test_helper"

# #846: Sidebar-Layout-Vorliebe pro Actor (ActorPreferences).
class ActorSidebarLayoutTest < ActiveSupport::TestCase
  def actor
    @actor ||= HumanActor.create!(name: "L", email: "l-#{SecureRandom.hex(3)}@t.local")
  end

  test "default layout matches SIDEBAR_ITEM_DEFAULTS and covers every item" do
    layout = actor.pref_sidebar_layout
    assert_equal %w[dashboard pinned history recent_topics], layout["pinned"]
    assert_equal "topics", layout["scroll"].first
    assert_empty layout["hidden"]
    all = layout.values.flatten
    assert_equal ActorPreferences::SIDEBAR_ITEM_IDS.sort, all.sort
    assert_equal all.uniq, all, "keine ID doppelt"
  end

  test "saved layout is honored, order preserved" do
    actor.update_preferences(
      "sidebar_layout" => { "pinned" => "tasks,dashboard", "scroll" => "topics", "hidden" => "tags" }
    )
    layout = actor.pref_sidebar_layout
    # gespeicherte Reihenfolge vorn; fehlende pinned-Defaults haengen hinten an.
    assert_equal %w[tasks dashboard], layout["pinned"].first(2)
    assert_equal ["tags"], layout["hidden"], "hidden bekommt keine Auto-Ergaenzung"
  end

  test "missing (newly added) ids are appended to their default section, visible" do
    # Layout ohne "tags" gespeichert -> tags fehlt und muss wieder auftauchen.
    actor.update_preferences(
      "sidebar_layout" => { "pinned" => "dashboard", "scroll" => "tasks", "hidden" => "" }
    )
    layout = actor.pref_sidebar_layout
    all = layout.values.flatten
    assert_includes all, "tags", "fehlende ID wird ergaenzt"
    assert_includes layout["scroll"], "tags", "und zwar sichtbar im Scrollbereich"
    refute_includes layout["hidden"], "tags"
    # Vollstaendigkeit bleibt gewahrt
    assert_equal ActorPreferences::SIDEBAR_ITEM_IDS.sort, all.sort
  end

  test "unknown ids are dropped and duplicates deduped across sections" do
    actor.update_preferences(
      "sidebar_layout" => { "pinned" => "dashboard,bogus", "scroll" => "dashboard,tasks", "hidden" => "" }
    )
    raw = actor.preferences["sidebar_layout"]
    refute_includes raw.values.flatten, "bogus"
    # dashboard nur einmal (erste Nennung gewinnt: pinned)
    assert_includes raw["pinned"], "dashboard"
    refute_includes raw["scroll"], "dashboard"
  end

  test "layout accepts array input (not only comma strings)" do
    actor.update_preferences(
      "sidebar_layout" => { "pinned" => %w[history dashboard], "scroll" => %w[tasks], "hidden" => [] }
    )
    assert_equal %w[history dashboard], actor.pref_sidebar_layout["pinned"].first(2)
  end
end
