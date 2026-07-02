module Inbox
  module Bib
    # Strategy 5 (Last Resort): bibliografische Daten aus dem Dateinamen
    # raten. Erkennt typische Citavi-/Zotero-Patterns wie
    #   "Doe2024Climate.pdf", "Doe_2024_Climate.pdf",
    #   "Doe - 2024 - Climate Change.pdf", "2024_Doe_Climate.pdf".
    # Wenn nichts erkannt wird, geben wir wenigstens den Filename als
    # Title zurück, damit das KI eingehängt werden kann.
    module Filename
      YEAR_RE = /(?<year>(?:19|20)\d{2})/.freeze

      def self.call(item:, **_)
        original = item.payload["original_filename"].to_s.presence ||
                   item.external_path.to_s.split("/").last.to_s
        base = File.basename(original, ".*").to_s
        return nil if base.strip.empty?

        if (m = base.match(/\A(?<rest1>.+?)#{YEAR_RE.source}(?<rest2>.+)\z/x))
          family_part = m[:rest1].sub(/[\s_\-\.]+\z/, "")
          title_part  = m[:rest2].sub(/\A[\s_\-\.]+/, "")
          family      = family_part.split(/[\s_\-\.]+/).first.to_s.strip
          title       = title_part.split(/[\s_\-\.]+/).reject(&:empty?).join(" ").strip
          year        = m[:year].to_i
          return {
            csl_type:        "article-journal",
            title:           title.presence || base,
            issued_date:     (Date.new(year, 1, 1) rescue nil),
            issued_string:   m[:year],
            authors:         family.present? ? [{ given: nil, family: family }] : [],
            identifier:      nil
          }
        end

        # Kein Jahr → ganzer Filename als Title. Citavi-Stil-Fallback.
        {
          csl_type:   "article-journal",
          title:      base.gsub(/[_]+/, " ").strip,
          authors:    [],
          identifier: nil
        }
      end
    end
  end
end
