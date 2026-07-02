# #417 Iter 2 (Hans, 2026-05-30): Lucide-Icons on-demand cachen, wenn
# der User in den Tag-Icon-Settings einen Icon-Namen eingibt. Die
# Source ist die CDN-Variante von `lucide-static` — pro Icon eine SVG-
# Datei. Wir extrahieren den Inner-Content (alles zwischen
# `<svg ...>...</svg>`) und legen ein `_<name>.html.erb`-Partial im
# Standard-Ordner ab, damit der bestehende `icon`-Helper das Icon
# rendern kann wie jeden bereits installierten.
require "open-uri"

class LucideFetcher
  ICONS_DIR = Rails.root.join("app/views/shared/icons")
  CDN_URL   = "https://cdn.jsdelivr.net/npm/lucide-static@latest/icons/%s.svg".freeze
  TIMEOUT   = 5  # seconds

  # Stellt sicher, dass ein Icon-Partial existiert. Gibt true zurueck,
  # wenn das Partial vorher schon da war ODER erfolgreich nachgezogen
  # wurde; false bei Fetch-/Parse-Fehler.
  def self.ensure_icon(icon_name)
    name = icon_name.to_s.strip.downcase.gsub(/[^a-z0-9_-]/, "_")
    return false if name.empty?
    path = ICONS_DIR.join("_#{name}.html.erb")
    return true if path.exist?

    url = format(CDN_URL, name)
    svg = URI.open(url, read_timeout: TIMEOUT).read
    # Inner: alles zwischen <svg ...> und </svg>, gestripped.
    m = svg.match(/<svg[^>]*>(.*)<\/svg>/m)
    return false unless m
    inner = m[1].strip
    return false if inner.empty?

    File.write(path, "<%# Lucide #{name} (auto-imported) %>\n#{inner}\n")
    true
  rescue StandardError => e
    Rails.logger.warn "LucideFetcher: failed to fetch #{name}: #{e.class} #{e.message}"
    false
  end

  # Schluckt eine Liste — gibt Hash {name => true/false} zurueck.
  def self.ensure_all(names)
    Array(names).uniq.map { |n| [n.to_s, ensure_icon(n)] }.to_h
  end
end
