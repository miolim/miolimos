# #271: Vorlieben pro Actor — gespeichert in actors.preferences (jsonb).
# Zentral hier definiert: Default-Werte + Typkonvertierung + erlaubte
# Werte. Konsumenten (View / Controller / JS-data-Attribute) gehen ueber
# diese Helper, nicht direkt an die jsonb-Hash, damit Bezeichnungen
# stabil bleiben.
module ActorPreferences
  extend ActiveSupport::Concern

  # Card-Breiten in rem pro Card-Kind. Aktuelle Defaults entsprechen den
  # bisher hartcodierten Werten in den *_blade_card-Partials.
  CARD_WIDTH_DEFAULTS = {
    "task"          => 36,
    "topic"         => 36,
    "topic_list"    => 60,   # die Multi-Tab-Topic-Listen-Card ist breiter
    "topic_render"  => 60,   # #357: Rendering-Blade (Work-Tree-Render)
    "ki"            => 36,
    "ki_refs"       => 44,   # #343: Reference-Blade (KI)
    "topic_refs"    => 44,   # #352-follow: Reference-Blade (Topic-Work-Tree)
    "source"        => 36,
    "awaiting"      => 36,
    "communication" => 36,
    "list_tasks"    => 42,
    "list_default"  => 26
  }.freeze

  CARD_KINDS = CARD_WIDTH_DEFAULTS.keys.freeze

  # Wheel-Speed in {threshold, lock_ms}. Niedriger = empfindlicher.
  WHEEL_PRESETS = {
    "slow"   => { "threshold" => 60, "lock_ms" => 200 },
    "normal" => { "threshold" => 20, "lock_ms" => 110 },
    "fast"   => { "threshold" => 10, "lock_ms" => 60  }
  }.freeze

  SIDEBAR_CLICK_MODES = %w[navigate append].freeze

  # #619 (Hans, 2026-06-18): UI-Sprache pro Nutzer. Muss zu
  # config.i18n.available_locales passen. Default folgt der App-
  # Default-Locale (:de), wenn nichts gewaehlt ist.
  LOCALES = %w[de en].freeze

  def pref_locale
    val = preferences["locale"].to_s
    LOCALES.include?(val) ? val : I18n.default_locale.to_s
  end

  def pref_card_width(kind)
    (preferences.dig("card_widths", kind.to_s) ||
     CARD_WIDTH_DEFAULTS[kind.to_s] ||
     CARD_WIDTH_DEFAULTS["list_default"]).to_f
  end

  def pref_card_widths
    saved   = preferences["card_widths"] || {}
    CARD_WIDTH_DEFAULTS.each_with_object({}) do |(k, default), h|
      h[k] = (saved[k] || default).to_f
    end
  end

  def pref_wheel_preset
    val = preferences["wheel_preset"].to_s
    WHEEL_PRESETS.key?(val) ? val : "normal"
  end

  def pref_wheel
    WHEEL_PRESETS[pref_wheel_preset]
  end

  def pref_sidebar_click_mode
    val = preferences["sidebar_click_mode"].to_s
    SIDEBAR_CLICK_MODES.include?(val) ? val : "navigate"
  end

  # #373 Phase A (Hans, 2026-05-26): Anzeige-Schalter fuer den CM6-
  # Markdown-Editor. Default off — Phase A liefert noch keine eigenen
  # Decorations; sobald Phase B/C drin sind, kann der Default kippen.
  # URL-Param `?cm6=1`/`?cm6=0` ueberschreibt diese Pref pro Request.
  def pref_cm6_editor?
    preferences["cm6_editor"] == true
  end

  # #435 (Hans, 2026-06-01): Anzahl der "zuletzt geoeffneten Topics", die die
  # Sidebar im Sticky-Bereich zeigt. Default 5, 0 = aus, Obergrenze 20.
  SIDEBAR_RECENT_TOPICS_DEFAULT = 5
  SIDEBAR_RECENT_TOPICS_MAX     = 20

  def pref_sidebar_recent_topics_count
    raw = preferences["sidebar_recent_topics_count"]
    return SIDEBAR_RECENT_TOPICS_DEFAULT if raw.nil?
    raw.to_i.clamp(0, SIDEBAR_RECENT_TOPICS_MAX)
  end

  def update_preferences(updates)
    new_prefs = preferences.deep_dup
    updates.each do |key, value|
      case key.to_s
      when "card_widths"
        new_prefs["card_widths"] = (new_prefs["card_widths"] || {}).merge(
          value.to_h.transform_values { |v| v.to_f }.select { |k, _| CARD_KINDS.include?(k.to_s) }
        )
      when "wheel_preset"
        new_prefs["wheel_preset"] = value.to_s if WHEEL_PRESETS.key?(value.to_s)
      when "sidebar_click_mode"
        new_prefs["sidebar_click_mode"] = value.to_s if SIDEBAR_CLICK_MODES.include?(value.to_s)
      when "cm6_editor"
        new_prefs["cm6_editor"] = ActiveModel::Type::Boolean.new.cast(value)
      when "sidebar_recent_topics_count"
        new_prefs["sidebar_recent_topics_count"] = value.to_i.clamp(0, SIDEBAR_RECENT_TOPICS_MAX)
      when "locale"
        new_prefs["locale"] = value.to_s if LOCALES.include?(value.to_s)
      end
    end
    update!(preferences: new_prefs)
  end
end
