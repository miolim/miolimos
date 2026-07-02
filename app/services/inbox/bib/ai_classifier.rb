module Inbox
  module Bib
    # Strategy 4: Wenn DOI/ISBN/Embedded nichts liefern, lassen wir das
    # LLM den ersten Seitenausschnitt klassifizieren. Prompt verlangt
    # strenges JSON; bei Parse-Fehlern fällt die Strategie still durch
    # auf die nächste. Erkennt das LLM eine DOI/ISBN, übernehmen wir
    # die — den authoritativen CrossRef/OpenLibrary-Lookup macht der
    # User dann manuell (Phase B will hier nicht zwei API-Calls hängen).
    module AiClassifier
      MAX_CHARS = 4_000
      SYSTEM_PROMPT = <<~SYS.freeze
        Du extrahierst bibliografische Metadaten aus dem Anfang eines Dokuments
        (Titelseite / erste Druckseiten eines wissenschaftlichen Artikels, Buchs,
        Reports). Gib ausschließlich gültiges JSON zurück, keine Erklärungen.
        Felder (alle optional außer title — wenn unklar: null):
          type            (article-journal|book|chapter|paper-conference|report|thesis|manuscript|webpage)
          title           (string, erforderlich)
          container_title (Journal-/Buchname)
          publisher
          year            (int)
          authors         (Array von {given, family})
          doi
          isbn
          pages
          volume
          issue
          language        (zweistelliger Code, z.B. "en", "de")
          abstract
      SYS

      def self.call(text:, **_)
        return nil unless llm_available?
        snippet = text.to_s.strip[0, MAX_CHARS]
        return nil if snippet.empty?

        raw = Llm::ChatClient.complete(
          system:     SYSTEM_PROMPT,
          prompt:     "Klassifiziere folgendes Dokument-Snippet:\n\n```\n#{snippet}\n```\n\nNur JSON.",
          max_tokens: 1_024
        )
        json = extract_json(raw)
        return nil if json.blank?

        normalize(json)
      end

      def self.llm_available?
        Llm::ChatClient.detect_provider.present?
      rescue
        false
      end

      def self.extract_json(raw)
        return nil if raw.blank?
        s = raw.strip
        # LLMs umranden gern mit ```json …``` — herausziehen.
        if (m = s.match(/```(?:json)?\s*(\{.*\})\s*```/m))
          s = m[1]
        end
        JSON.parse(s)
      rescue JSON::ParserError
        # Letzter Versuch: alles ab erster `{` bis letzter `}` extrahieren.
        if raw =~ /\{.*\}/m
          JSON.parse(raw.match(/\{.*\}/m)[0]) rescue nil
        end
      end

      VALID_TYPES = %w[article-journal book chapter paper-conference report thesis manuscript webpage].freeze

      def self.normalize(j)
        type = VALID_TYPES.include?(j["type"]) ? j["type"] : "article-journal"
        year = j["year"].is_a?(Integer) ? j["year"] : j["year"].to_s.to_i
        date = (year.between?(1500, 2100) ? Date.new(year, 1, 1) : nil) rescue nil
        ident = nil
        if j["doi"].to_s.match?(/\A10\.\d/)
          ident = { scheme: "DOI",  value: j["doi"].to_s.strip }
        elsif j["isbn"].to_s.gsub(/[^\dXx]/, "").length.in?([10, 13])
          ident = { scheme: "ISBN", value: j["isbn"].to_s.gsub(/[^\dXx]/, "").upcase }
        end

        {
          csl_type:        type,
          title:           j["title"].to_s.strip,
          container_title: j["container_title"].to_s.strip.presence,
          publisher:       j["publisher"].to_s.strip.presence,
          issued_date:     date,
          issued_string:   year.positive? ? year.to_s : nil,
          volume:          j["volume"].to_s.strip.presence,
          issue:           j["issue"].to_s.strip.presence,
          pages:           j["pages"].to_s.strip.presence,
          abstract:        j["abstract"].to_s.strip.presence,
          language:        j["language"].to_s.strip.presence,
          authors:         Array(j["authors"]).map { |a|
            { given: a["given"].to_s.strip, family: a["family"].to_s.strip }
          }.reject { |a| a[:given].blank? && a[:family].blank? },
          identifier:      ident
        }
      end
    end
  end
end
