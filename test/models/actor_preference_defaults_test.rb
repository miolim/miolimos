require "test_helper"

# #1500 (aus immoos uebernommen, Hans): „Im Moment macht jeder Nutzer die Einstellungen in den
# Vorlieben für sich selbst, ausgehend von einem ‚organisch gewachsenen‘
# Standard. Ich würde gern als Admin diesen Standard für neue Nutzer vorher auf
# meinen aktuellen Stand festlegen können."
#
# Die tragende Entscheidung: Die Vorgabe wirkt bei der ANLAGE, nicht beim
# Lesen. Wer schon da ist, behält seine Einstellungen — auch die, die er nie
# angefasst hat. Genau diese Grenze prüfen die Tests hier.
class ActorPreferenceDefaultsTest < ActiveSupport::TestCase
  def actor(**attrs)
    HumanActor.create!({ name: "Neu", email: "n-#{SecureRandom.hex(4)}@t.local",
                         password: "secretsecret" }.merge(attrs))
  end

  test "ohne hinterlegte Vorgabe startet ein neuer Nutzer wie bisher" do
    assert_empty Actor.global_defaults
    assert_empty actor.preferences
  end

  test "ein neuer Nutzer erbt die hinterlegte Vorgabe" do
    Actor.global_defaults = { "locale" => "en", "wheel_preset" => "fast" }

    neu = actor

    assert_equal "en",   neu.pref_locale
    assert_equal "fast", neu.pref_wheel_preset
  end

  test "wer schon da ist, bleibt unberuehrt" do
    alt = actor
    assert_equal I18n.default_locale.to_s, alt.pref_locale

    Actor.global_defaults = { "locale" => "en" }

    assert_equal I18n.default_locale.to_s, alt.reload.pref_locale,
                 "die Vorgabe wirkt bei der Anlage, nicht rueckwirkend"
  end

  test "was bei der Anlage ausdruecklich mitgegeben wird, gewinnt" do
    Actor.global_defaults = { "locale" => "en", "wheel_preset" => "fast" }

    neu = actor(preferences: { "locale" => "de" })

    assert_equal "de",   neu.pref_locale,        "die Mitgabe schlaegt die Vorgabe"
    assert_equal "fast", neu.pref_wheel_preset,  "der Rest der Vorgabe bleibt"
  end

  # Dieselben Regeln wie beim Speichern am Nutzer — sonst koennte hier etwas
  # landen, das dort nie ankaeme.
  test "die Vorgabe wird nach denselben Regeln gefiltert wie eine Vorliebe" do
    Actor.global_defaults = { "locale" => "klingonisch", "unbekannt" => "x",
                              "wheel_preset" => "fast",
                              "card_widths" => { "task" => 999, "böser key!" => 30 } }

    vorgabe = Actor.global_defaults

    assert_equal %w[card_widths wheel_preset], vorgabe.keys.sort
    assert_equal 120.0, vorgabe["card_widths"]["task"], "auf den erlaubten Bereich geklemmt"
    assert_nil vorgabe["card_widths"]["böser key!"]
  end

  test "kaputtes JSON im Speicher laesst die Anlage nicht scheitern" do
    Setting.set(ActorPreferences::DEFAULTS_SETTING_KEY, "{kein json")

    assert_empty Actor.global_defaults
    assert_empty actor.preferences
  end

  test "Vorgabe entfernen setzt neue Nutzer auf die eingebauten Werte zurueck" do
    Actor.global_defaults = { "locale" => "en" }
    assert Actor.global_defaults?

    Actor.reset_global_defaults!

    assert_not Actor.global_defaults?
    assert_equal I18n.default_locale.to_s, actor.pref_locale
  end

  # #1500: Hans ausdruecklich — „das wird natuerlich nicht in den Standard
  # uebernommen". Es kann gar nicht: Die Selbst-KI ist eine Spalte am Actor,
  # keine Vorliebe.
  test "die Selbst-KI gehoert nicht zur Vorgabe" do
    Actor.global_defaults = { "locale" => "en", "person_ki_uuid" => SecureRandom.uuid }

    assert_not_includes Actor.global_defaults.keys, "person_ki_uuid"
    assert_nil actor.person_ki_uuid
  end
end
