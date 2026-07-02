require "net/http"
require "uri"
require "json"

module Inbox
  module Bib
    # Strategy 1: DOI aus den ersten Seiten regexen, CrossRef abfragen,
    # auf das normalisierte Pipeline-Format mappen.
    module DoiCrossref
      DOI_RE       = /\b10\.\d{4,9}\/[-._;()\/:A-Z0-9]+/i
      CROSSREF_URL = "https://api.crossref.org/works/".freeze
      USER_AGENT   = "miolimOS/#{Miolimos::VERSION} (+https://github.com/miolim/miolimos)".freeze

      CSL_TYPE_MAP = {
        "journal-article"     => "article-journal",
        "book"                => "book",
        "monograph"           => "book",
        "edited-book"         => "book",
        "reference-book"      => "book",
        "book-chapter"        => "chapter",
        "proceedings-article" => "paper-conference",
        "proceedings"         => "paper-conference",
        "report"              => "report",
        "dataset"             => "dataset",
        "thesis-dissertation" => "thesis",
        "posted-content"      => "manuscript",
        "standard"            => "report"
      }.freeze

      def self.call(text:, **_)
        doi  = extract_doi(text)
        return nil if doi.blank?
        meta = lookup(doi)
        return nil if meta.blank?
        normalize(meta, doi: doi)
      end

      # PDF-Texte hängen oft Satz-Interpunktion an die DOI dran — trimmen.
      def self.extract_doi(text)
        m = text.to_s[DOI_RE]
        m && m.sub(/[\.,;:\)\]]+\z/, "")
      end

      def self.lookup(doi)
        uri = URI.parse("#{CROSSREF_URL}#{URI.encode_www_form_component(doi)}")
        res = Net::HTTP.start(uri.host, uri.port,
                              use_ssl: true, open_timeout: 5, read_timeout: 15) do |http|
          http.request(Net::HTTP::Get.new(uri, "User-Agent" => USER_AGENT, "Accept" => "application/json"))
        end
        return nil if res.code.to_s == "404"
        raise "CrossRef HTTP #{res.code}" unless res.is_a?(Net::HTTPSuccess)
        JSON.parse(res.body)["message"]
      end

      def self.normalize(meta, doi:)
        issued = parse_issued(meta)
        url    = meta["URL"].to_s.strip.presence ||
                 (meta["resource"].is_a?(Hash) ? meta.dig("resource", "primary", "URL") : nil)
        {
          csl_type:        CSL_TYPE_MAP[meta["type"]] || "article-journal",
          title:           Array(meta["title"]).first.to_s.strip,
          container_title: Array(meta["container-title"]).first.to_s.strip.presence,
          publisher:       meta["publisher"].to_s.strip.presence,
          publisher_place: meta["publisher-location"].to_s.strip.presence,
          issued_date:     issued[:date],
          issued_string:   issued[:string],
          volume:          meta["volume"].to_s.strip.presence,
          issue:           meta["issue"].to_s.strip.presence,
          pages:           meta["page"].to_s.strip.presence,
          abstract:        meta["abstract"].to_s.gsub(/<[^>]+>/, "").strip.presence,
          language:        meta["language"].to_s.strip.presence,
          url:             url.to_s.strip.presence,
          authors:         Array(meta["author"]).map { |a| { given: a["given"].to_s.strip, family: a["family"].to_s.strip } },
          identifier:      { scheme: "DOI", value: doi }
        }
      end

      def self.parse_issued(meta)
        parts = meta.dig("published-print", "date-parts", 0) ||
                meta.dig("published-online", "date-parts", 0) ||
                meta.dig("issued",  "date-parts", 0) ||
                meta.dig("created", "date-parts", 0)
        return { date: nil, string: nil } if parts.blank?
        year, month, day = parts
        date =
          if year && month && day then (Date.new(year.to_i, month.to_i, day.to_i) rescue nil)
          elsif year && month     then (Date.new(year.to_i, month.to_i, 1) rescue nil)
          elsif year              then (Date.new(year.to_i, 1, 1) rescue nil)
          end
        { date: date, string: parts.compact.join("-").presence }
      end
    end
  end
end
