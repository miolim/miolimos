require "test_helper"

# #1582: Startseiten-Vorliebe — Dashboard als Standard, leer und die
# Seitenleisten-Einträge mit eigener Seite sind wählbar.
class ActorStartStackTest < ActiveSupport::TestCase
  setup do
    @actor = HumanActor.create!(name: "Start", email: "start-#{SecureRandom.hex(3)}@test.local")
  end

  test "ohne Wahl startet das Dashboard" do
    assert_equal "dashboard", @actor.pref_start_stack
  end

  test "leer und Seitenleisten-Einträge lassen sich wählen" do
    @actor.update_preferences("start_stack" => "empty")
    assert_equal "empty", @actor.reload.pref_start_stack

    @actor.update_preferences("start_stack" => "tasks")
    assert_equal "tasks", @actor.reload.pref_start_stack
  end

  test "unbekannte Werte und Einträge ohne eigene Seite werden nicht gespeichert" do
    @actor.update_preferences("start_stack" => "tasks")
    @actor.update_preferences("start_stack" => "recent_topics")
    @actor.update_preferences("start_stack" => "javascript:alert(1)")
    assert_equal "tasks", @actor.reload.pref_start_stack
  end
end
