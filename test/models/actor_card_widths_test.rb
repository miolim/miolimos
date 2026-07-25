require "test_helper"

# #1152: Standard-Kartenbreiten — neben den festen Default-Kinds speichert
# der Blade-Stack per STRG-Doppelklick auch dynamische Client-Kinds
# ("list:knowledge_items", "document", …) als User-Preference.
class ActorCardWidthsTest < ActiveSupport::TestCase
  setup do
    @actor = HumanActor.create!(name: "Widths", email: "widths@test.local")
  end

  test "dynamisches Kind wird gespeichert und ausgeliefert" do
    @actor.update_preferences("card_widths" => { "list:knowledge_items" => "31" })
    assert_equal 31.0, @actor.reload.preferences.dig("card_widths", "list:knowledge_items")
    assert_equal 31.0, @actor.pref_card_widths["list:knowledge_items"]
  end

  test "Default-Kinds bleiben in pref_card_widths erhalten und ueberschreibbar" do
    @actor.update_preferences("card_widths" => { "ki" => "48" })
    widths = @actor.reload.pref_card_widths
    assert_equal 48.0, widths["ki"]
    assert_equal ActorPreferences::CARD_WIDTH_DEFAULTS["task"].to_f, widths["task"]
  end

  test "ungueltige Kind-Namen werden verworfen" do
    @actor.update_preferences("card_widths" => { "böse kind!" => "30", "a" * 65 => "30" })
    assert_empty @actor.reload.preferences["card_widths"] || {}
  end

  test "Werte werden auf den Formular-Bereich geklemmt" do
    @actor.update_preferences("card_widths" => { "ki" => "999", "task" => "1" })
    assert_equal 120.0, @actor.reload.preferences.dig("card_widths", "ki")
    assert_equal 16.0,  @actor.preferences.dig("card_widths", "task")
  end
end
