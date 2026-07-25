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

  # #1152-Aufraeumen: die Default-Tabelle traegt die Kind-Namen, unter denen
  # der Blade-Stack die Breiten tatsaechlich nachschlaegt.
  test "Default-Tabelle nutzt die Frontend-Kind-Namen" do
    keys = ActorPreferences::CARD_WIDTH_DEFAULTS.keys
    %w[src list:tasks list:topic].each { |k| assert_includes keys, k }
    %w[source list_tasks topic_list list_default].each { |k| refute_includes keys, k }
  end

  test "Migration benennt gespeicherte Alt-Keys um" do
    require Rails.root.join("db/migrate/20260725231000_rename_card_width_pref_keys.rb").to_s
    @actor.update_columns(preferences: { "card_widths" => {
      "source" => 40, "src" => 38, "list_tasks" => 50, "list_default" => 26, "ki" => 44
    } })
    migration = RenameCardWidthPrefKeys.new
    migration.instance_variable_set(:@_verbose, false)
    ActiveRecord::Migration.suppress_messages { migration.up }
    cw = @actor.reload.preferences["card_widths"]
    assert_equal 38, cw["src"], "bestehender neuer Key gewinnt gegen den alten"
    assert_equal 50, cw["list:tasks"], "Alt-Key ohne neuen Gegenpart wird umbenannt"
    assert_equal 44, cw["ki"], "unbeteiligte Kinds bleiben unangetastet"
    %w[source list_tasks list_default].each { |k| refute cw.key?(k), "#{k} muss weg sein" }
  end
end
