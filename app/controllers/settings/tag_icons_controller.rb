# #417 (Hans, 2026-05-30): Settings-Tab zum Pflegen der Tag→Icon-Map.
# Wenn ein Icon-Name eingetragen wird, der noch nicht als Partial
# existiert, holt der Controller die SVG via LucideFetcher vom CDN
# und legt ein neues `_<name>.html.erb` an.
class Settings::TagIconsController < Settings::BaseController
  # #613: Einstellungen sind ein Blade-Stack — die alte Reiter-URL
  # leitet auf den Stack mit geöffnetem Bereichs-Blade.
  def index
    redirect_to settings_path(stack: "list:settings,settings:tag_icons")
  end

  def update
    # Form sendet zwei parallele Arrays (tags[] und icons[]). Positionen
    # zippen, leere Zeilen verwerfen, lowercase normalisieren.
    tags  = Array(params[:tags])
    icons = Array(params[:icons])
    map = tags.zip(icons)
                .reject { |t, i| t.to_s.strip.empty? || i.to_s.strip.empty? }
                .to_h { |t, i| [t.to_s.strip.downcase, i.to_s.strip.downcase] }

    fetched = LucideFetcher.ensure_all(map.values)
    missing = fetched.reject { |_, ok| ok }.keys

    Setting.set("tag_icons", map.to_json)

    if missing.any?
      flash[:alert] = "Gespeichert. Nicht ladbare Icons: #{missing.join(', ')} — Name pruefen (Lucide-Icon-Namen, lowercase, Bindestrich oder Unterstrich)."
    else
      flash[:notice] = "Tag-Icons gespeichert."
    end
    redirect_to settings_tag_icons_path
  end

  private

  # Setting ist kein eigener Ressourcen-Typ im Capability-System; wir
  # haengen den Zugriff an "Actor" (wie Preferences).
  def controller_resource_type
    "Actor"
  end

  def controller_action_to_capability
    return "update" if action_name == "update"
    "read"
  end
end
