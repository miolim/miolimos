require "open3"

module Inbox
  module Bib
    # Strategy 3: Eingebettete Metadaten der PDF (`/Info`-Dict) per
    # `pdfinfo` lesen. Nur verwerten, wenn ein nicht-trivialer Title
    # drinsteht — PDFs aus MS-Word setzen den Title oft auf den
    # Dateinamen oder "untitled", das wäre kein Gewinn gegenüber dem
    # Filename-Fallback.
    module EmbeddedInfo
      JUNK_TITLE = /\A\s*(untitled|microsoft word|document\d*|temp\d*|\.tex)/i.freeze

      def self.call(path:, **_)
        info = read_info(path)
        return nil if info.blank?
        title = info["Title"].to_s.strip
        return nil if title.empty? || title.match?(JUNK_TITLE)
        return nil if title.length < 4

        date_str = info["CreationDate"].to_s
        date     = parse_pdf_date(date_str)
        authors  = split_authors(info["Author"].to_s)
        kw       = info["Keywords"].to_s.strip

        {
          csl_type:        "book",
          title:           title,
          container_title: nil,
          publisher:       nil,
          issued_date:     date,
          issued_string:   date_str.presence,
          abstract:        info["Subject"].to_s.strip.presence,
          language:        nil,
          url:             nil,
          authors:         authors,
          identifier:      nil,
          embedded_keywords: kw.presence
        }
      end

      def self.read_info(path)
        out, _err, status = Open3.capture3("pdfinfo", "-enc", "UTF-8", path)
        return nil unless status.success?
        out.lines.each_with_object({}) do |line, acc|
          m = line.match(/\A([A-Za-z][A-Za-z0-9 _-]*?):\s+(.*)\z/)
          acc[m[1].strip] = m[2].strip if m
        end
      end

      # pdfinfo gibt das Datum als "Mon Mar 15 12:34:56 2024 UTC" aus.
      def self.parse_pdf_date(s)
        return nil if s.blank?
        Date.parse(s) rescue nil
      end

      # PDF /Info/Author ist ein Freitext-Feld — oft "John Doe, Jane Roe"
      # oder "Doe, J.; Roe, J." oder einzelne Person. Wir splitten an
      # Komma/Semikolon/&/and.
      def self.split_authors(s)
        return [] if s.blank?
        s.split(/[,;]|\s+(?:and|&)\s+/i).map(&:strip).reject(&:empty?).map do |name|
          parts = name.split(/\s+/)
          if parts.size == 1
            { given: nil, family: parts.first }
          else
            { given: parts[0..-2].join(" "), family: parts.last }
          end
        end
      end
    end
  end
end
