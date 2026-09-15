require "test_helper"

# #1612 (Hans): freie, aufklappbare Zwischenüberschriften in der Sidebar,
# definiert in den Vorlieben. Klappzustand in den Vorlieben (a), bestehende
# Nutzer starten ohne Überschriften (b).
class ActorSidebarHeadings1612Test < ActiveSupport::TestCase
  def actor
    @actor ||= HumanActor.create!(name: "H", email: "h-#{SecureRandom.hex(3)}@t.local")
  end

  test "ohne Wahl gibt es keine Überschriften (leer starten)" do
    assert_empty actor.pref_sidebar_headings
    assert_empty actor.pref_sidebar_collapsed_headings
    assert_empty actor.pref_sidebar_layout.values.flatten.select { |id| ActorPreferences.sidebar_heading_id?(id) }
  end

  test "eine Überschrift steht im Layout an ihrer Stelle, mit Namen" do
    actor.update_preferences(
      "sidebar_headings" => { "a1b2c3d4" => "Arbeit" },
      "sidebar_layout"   => { "pinned" => "dashboard", "scroll" => "heading:a1b2c3d4,tasks,topics", "hidden" => "" }
    )
    actor.reload
    assert_equal({ "a1b2c3d4" => "Arbeit" }, actor.pref_sidebar_headings)
    assert_equal %w[heading:a1b2c3d4 tasks topics], actor.pref_sidebar_layout["scroll"].first(3)
  end

  test "Reihenfolge der Schlüssel spielt keine Rolle — Layout vor Überschriften geht auch" do
    actor.update_preferences(
      "sidebar_layout"   => { "pinned" => "", "scroll" => "heading:a1b2c3d4,tasks", "hidden" => "" },
      "sidebar_headings" => { "a1b2c3d4" => "Arbeit" }
    )
    assert_includes actor.reload.pref_sidebar_layout["scroll"], "heading:a1b2c3d4"
  end

  test "unbekannte, kaputte und namenlose Überschriften fallen weg" do
    actor.update_preferences(
      "sidebar_headings" => { "a1b2c3d4" => "  ", "zzzz" => "Kaputt", "b1b2c3d4" => "Gut" },
      "sidebar_layout"   => { "pinned" => "", "scroll" => "heading:a1b2c3d4,heading:zzzz,heading:b1b2c3d4,heading:c1c2c3c4,tasks", "hidden" => "" }
    )
    actor.reload
    assert_equal({ "b1b2c3d4" => "Gut" }, actor.pref_sidebar_headings)
    headings_im_layout = actor.pref_sidebar_layout.values.flatten.select { |id| ActorPreferences.sidebar_heading_id?(id) }
    assert_equal %w[heading:b1b2c3d4], headings_im_layout
  end

  test "Namen werden bereinigt und gekürzt" do
    lang = "x" * 60
    actor.update_preferences(
      "sidebar_headings" => { "a1b2c3d4" => "  Viel   Platz  ", "b1b2c3d4" => lang },
      "sidebar_layout"   => { "pinned" => "", "scroll" => "heading:a1b2c3d4,heading:b1b2c3d4", "hidden" => "" }
    )
    h = actor.reload.pref_sidebar_headings
    assert_equal "Viel Platz", h["a1b2c3d4"]
    assert_equal ActorPreferences::SIDEBAR_HEADING_NAME_MAX, h["b1b2c3d4"].length
  end

  test "beim Speichern des Layouts verschwinden Überschriften, die nicht mehr darin stehen" do
    actor.update_preferences(
      "sidebar_headings" => { "a1b2c3d4" => "Alt", "b1b2c3d4" => "Bleibt" },
      "sidebar_layout"   => { "pinned" => "", "scroll" => "heading:a1b2c3d4,heading:b1b2c3d4", "hidden" => "" }
    )
    # Im Editor entfernt: das Formular schickt die Überschrift nicht mehr mit.
    actor.update_preferences(
      "sidebar_headings" => { "b1b2c3d4" => "Bleibt" },
      "sidebar_layout"   => { "pinned" => "", "scroll" => "heading:b1b2c3d4", "hidden" => "" }
    )
    assert_equal({ "b1b2c3d4" => "Bleibt" }, actor.reload.pref_sidebar_headings)

    # Alle entfernt: dann fehlt der Schlüssel im Formular ganz.
    actor.update_preferences("sidebar_layout" => { "pinned" => "", "scroll" => "tasks", "hidden" => "" })
    assert_empty actor.reload.pref_sidebar_headings
  end

  test "Klappzustand: nur bekannte Überschriften, als Text oder Liste" do
    actor.update_preferences(
      "sidebar_headings" => { "a1b2c3d4" => "Arbeit", "b1b2c3d4" => "Privat" },
      "sidebar_layout"   => { "pinned" => "", "scroll" => "heading:a1b2c3d4,heading:b1b2c3d4", "hidden" => "" }
    )
    actor.update_preferences("sidebar_collapsed_headings" => "a1b2c3d4,deadbeef,")
    assert_equal %w[a1b2c3d4], actor.reload.pref_sidebar_collapsed_headings

    actor.update_preferences("sidebar_collapsed_headings" => %w[b1b2c3d4 a1b2c3d4 b1b2c3d4])
    assert_equal %w[b1b2c3d4 a1b2c3d4], actor.reload.pref_sidebar_collapsed_headings

    actor.update_preferences("sidebar_collapsed_headings" => "")
    assert_empty actor.reload.pref_sidebar_collapsed_headings
  end

  test "Umklappen lässt Layout und Überschriften unberührt" do
    actor.update_preferences(
      "sidebar_headings" => { "a1b2c3d4" => "Arbeit" },
      "sidebar_layout"   => { "pinned" => "", "scroll" => "heading:a1b2c3d4,tasks", "hidden" => "" }
    )
    actor.update_preferences("sidebar_collapsed_headings" => "a1b2c3d4")
    actor.reload
    assert_equal({ "a1b2c3d4" => "Arbeit" }, actor.pref_sidebar_headings)
    assert_equal %w[heading:a1b2c3d4 tasks], actor.pref_sidebar_layout["scroll"].first(2)
  end

  # Hans: „Das kann dann ja für neue Nutzer in den Standard übernommen werden."
  test "der Standard für neue Nutzer (#1500) nimmt Überschriften und Klappzustand mit" do
    vorlage = HumanActor.create!(name: "V", email: "v-#{SecureRandom.hex(3)}@t.local")
    vorlage.update_preferences(
      "sidebar_headings" => { "a1b2c3d4" => "Arbeit" },
      "sidebar_layout"   => { "pinned" => "dashboard", "scroll" => "heading:a1b2c3d4,tasks", "hidden" => "" }
    )
    vorlage.update_preferences("sidebar_collapsed_headings" => "a1b2c3d4")
    Actor.global_defaults = vorlage.reload.preferences

    neu = HumanActor.create!(name: "N", email: "n-#{SecureRandom.hex(3)}@t.local")
    assert_equal({ "a1b2c3d4" => "Arbeit" }, neu.pref_sidebar_headings)
    assert_includes neu.pref_sidebar_layout["scroll"], "heading:a1b2c3d4"
    assert_equal %w[a1b2c3d4], neu.pref_sidebar_collapsed_headings
  ensure
    Actor.reset_global_defaults!
  end
end
