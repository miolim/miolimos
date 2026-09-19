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
  # #1675: auf eine Version FESTGELEGT statt `@latest` — was heute geprüft ist,
  # ist morgen dasselbe. Anheben per LUCIDE_STATIC_VERSION oder hier.
  VERSION   = ENV.fetch("LUCIDE_STATIC_VERSION", "1.47.0")
  CDN_URL   = "https://cdn.jsdelivr.net/npm/lucide-static@#{VERSION}/icons/%s.svg".freeze

  # #1675: Das Ergebnis wird als ERB-Partial geschrieben — also als Code, den
  # der Server ausführt. Durch kommt deshalb nur, was ein Strich-Icon braucht.
  ERLAUBTE_ELEMENTE  = %w[path circle rect line polyline polygon ellipse g].freeze
  ERLAUBTE_ATTRIBUTE = %w[d cx cy r rx ry x y x1 y1 x2 y2 width height points transform
                          fill stroke stroke-width stroke-linecap stroke-linejoin].freeze
  HARMLOSER_WERT     = /\A[\w\s.,\-+()#%]*\z/
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
    inner = bereinige(svg)
    return false if inner.blank?

    File.write(path, "<%# Lucide #{name} (auto-imported, lucide-static #{VERSION}) %>\n#{inner}\n")
    true
  rescue StandardError => e
    Rails.logger.warn "LucideFetcher: failed to fetch #{name}: #{e.class} #{e.message}"
    false
  end

  # #1675: Das gelieferte SVG NEU AUFBAUEN statt durchreichen: nur erlaubte
  # Formen mit erlaubten Attributen und harmlosen Werten. Alles andere —
  # `<%`, Skripte, Ereignis-Attribute, Verweise, Fremdelemente — entfällt, weil
  # es gar nicht erst übernommen wird. nil, wenn keine Form übrig bleibt.
  def self.bereinige(svg)
    require "nokogiri"
    doc   = Nokogiri::XML(svg.to_s) { |cfg| cfg.nonet.recover }
    wurzel = doc.root
    return nil unless wurzel&.name == "svg"
    doc.remove_namespaces!
    formen = wurzel.element_children.filter_map { |knoten| erlaubte_form(knoten) }
    formen.presence&.join("\n")
  end

  def self.erlaubte_form(knoten)
    return nil unless ERLAUBTE_ELEMENTE.include?(knoten.name)
    attribute = knoten.attribute_nodes.filter_map do |a|
      next unless ERLAUBTE_ATTRIBUTE.include?(a.name) && a.value.match?(HARMLOSER_WERT)
      %(#{a.name}="#{a.value}")
    end
    kinder = knoten.name == "g" ? knoten.element_children.filter_map { |k| erlaubte_form(k) } : []
    return nil if knoten.name == "g" && kinder.empty?
    offen = ["<#{knoten.name}", *attribute].join(" ")
    kinder.empty? ? "#{offen} />" : "#{offen}>#{kinder.join}</#{knoten.name}>"
  end
  private_class_method :erlaubte_form

  # Schluckt eine Liste — gibt Hash {name => true/false} zurueck.
  def self.ensure_all(names)
    Array(names).uniq.map { |n| [n.to_s, ensure_icon(n)] }.to_h
  end
end
