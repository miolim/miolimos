require "net/http"
require "uri"
require "json"

module Inbox
  module Bib
    # Strategy 2: ISBN aus den ersten Seiten regexen (Cover/Impressum
    # tragen die fast immer), per OpenLibrary-Bibkeys-API auflösen. Wir
    # validieren die Prüfziffer, damit Telefonnummern und Bestellnummern
    # nicht versehentlich als ISBN durchgehen.
    module IsbnOpenlibrary
      # Erfasst ISBN-13 (97[89] + 10 Ziffern) und ISBN-10 (9 Ziffern + X).
      # Bindestriche/Leerzeichen werden später entfernt.
      ISBN_RE = /
        (?:ISBN[-:\s]*(?:13|10)?[-:\s]*)?
        (?:
          (?:97[89][\s\-]?){1}(?:\d[\s\-]?){9}\d        # ISBN-13 mit optionalen Trennern
          |
          (?:\d[\s\-]?){9}[\dXx]                        # ISBN-10
        )
      /xi.freeze

      OL_URL     = "https://openlibrary.org/api/books".freeze
      USER_AGENT = "miolimOS/1.0 (mailto:hans@miolim.de)".freeze

      def self.call(text:, **_)
        isbn = find_valid_isbn(text)
        return nil if isbn.blank?
        meta = lookup(isbn)
        return nil if meta.blank?
        normalize(meta, isbn: isbn)
      end

      def self.find_valid_isbn(text)
        text.to_s.scan(ISBN_RE).each do |m|
          digits = m.gsub(/[^0-9Xx]/, "").upcase
          return digits if (digits.length == 13 && valid_isbn13?(digits)) ||
                           (digits.length == 10 && valid_isbn10?(digits))
        end
        nil
      end

      def self.valid_isbn13?(d)
        return false unless d =~ /\A\d{13}\z/
        sum = d.each_char.with_index.sum { |c, i| c.to_i * (i.even? ? 1 : 3) }
        sum % 10 == 0
      end

      def self.valid_isbn10?(d)
        return false unless d =~ /\A\d{9}[\dX]\z/
        sum = d.each_char.with_index.sum do |c, i|
          v = c == "X" ? 10 : c.to_i
          v * (10 - i)
        end
        sum % 11 == 0
      end

      def self.lookup(isbn)
        bibkey = "ISBN:#{isbn}"
        uri = URI.parse("#{OL_URL}?bibkeys=#{URI.encode_www_form_component(bibkey)}&format=json&jscmd=data")
        res = Net::HTTP.start(uri.host, uri.port,
                              use_ssl: true, open_timeout: 5, read_timeout: 15) do |http|
          http.request(Net::HTTP::Get.new(uri, "User-Agent" => USER_AGENT, "Accept" => "application/json"))
        end
        raise "OpenLibrary HTTP #{res.code}" unless res.is_a?(Net::HTTPSuccess)
        parsed = JSON.parse(res.body)
        parsed[bibkey]
      end

      # OpenLibrary-"data"-Format: title, subtitle, authors:[{name}],
      # publishers:[{name}], publish_date, publish_places:[{name}],
      # url, number_of_pages.
      def self.normalize(meta, isbn:)
        title     = [meta["title"], meta["subtitle"]].reject(&:blank?).join(": ")
        publisher = Array(meta["publishers"]).first&.dig("name").to_s.strip
        place     = Array(meta["publish_places"]).first&.dig("name").to_s.strip
        date_str  = meta["publish_date"].to_s.strip
        year      = date_str.scan(/\d{4}/).first
        date      = year ? (Date.new(year.to_i, 1, 1) rescue nil) : nil
        authors   = Array(meta["authors"]).map { |a| split_name(a["name"].to_s) }

        {
          csl_type:        "book",
          title:           title.to_s.strip,
          container_title: nil,
          publisher:       publisher.presence,
          publisher_place: place.presence,
          issued_date:     date,
          issued_string:   date_str.presence,
          pages:           meta["number_of_pages"]&.to_s,
          url:             meta["url"].to_s.strip.presence,
          authors:         authors,
          identifier:      { scheme: "ISBN", value: isbn }
        }
      end

      # OpenLibrary gibt Autorennamen als einzelnen String — wir splitten
      # "Vorname Nachname"-Form heuristisch. Bei Mehr-Wort-Vornamen geht
      # das letzte Wort ins family, alle vorigen ins given.
      def self.split_name(name)
        parts = name.strip.split(/\s+/)
        return { given: nil, family: nil } if parts.empty?
        return { given: nil, family: parts.first } if parts.size == 1
        { given: parts[0..-2].join(" "), family: parts.last }
      end
    end
  end
end
