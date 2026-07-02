module Inbox
  module Bib
    # Strategy-Pipeline für die bibliografische Anreicherung einer PDF
    # (#65 Phase B). Strategien werden in Reihenfolge probiert; die erste,
    # die ein verwertbares Ergebnis (Title gesetzt) liefert, gewinnt.
    # Strategien werfen lieber, als nil zurückzugeben — Pipeline fängt's
    # und versucht die nächste.
    #
    # Normalisiertes Ergebnis (Hash):
    #   provenance:      "crossref" | "openlibrary" | "embedded" | "ai" | "filename"
    #   csl_type:        String   (Source::CSL_TYPES)
    #   title:           String   (required)
    #   container_title: String?
    #   publisher:       String?
    #   publisher_place: String?
    #   issued_date:     Date?
    #   issued_string:   String?
    #   volume:          String?
    #   issue:           String?
    #   pages:           String?
    #   abstract:        String?
    #   language:        String?
    #   url:             String?
    #   authors:         Array<{given:, family:}>
    #   identifier:      { scheme:, value: } | nil
    class Pipeline
      def self.strategies
        [DoiCrossref, IsbnOpenlibrary, EmbeddedInfo, AiClassifier, Filename]
      end

      def self.call(item:, path:, text:)
        strategies.each do |strat|
          begin
            result = strat.call(item: item, path: path, text: text)
          rescue => e
            Rails.logger.warn("Inbox::Bib::#{strat.name&.demodulize || strat}: #{e.class} #{e.message}")
            next
          end
          next if result.blank?
          next if result[:title].to_s.strip.empty?
          result[:provenance] ||= strat.name&.demodulize&.underscore || "unknown"
          return result
        end
        nil
      end
    end
  end
end
