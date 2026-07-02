require "net/http"
require "uri"

module Inbox
  module Processors
    # #799 (Hans): Importer für Links auf Markdown-Dateien (z. B.
    # https://europe2031.ai/agents/scenario.md). Moderne Seiten bieten .md
    # als KI-freundliche Variante an. Statt HTML-Clip (WebClip zerlegt die
    # Formatierung) wird die rohe .md geladen und formattreu als Wissens-KI
    # angelegt. Frontmatter (falls vorhanden) wird interpretiert; Titel sonst
    # aus der ersten H1 bzw. dem Dateinamen; die Quell-URL wird als Source
    # verlinkt.
    class MarkdownUrl < ProcessorBase
      def self.kind        = "markdown_url"
      def self.label       = "Markdown-Datei importieren"
      def self.description = "Lädt eine .md-Datei von der URL und legt sie formattreu als Wissens-KI an (statt HTML-Clip)."

      # Cheap (kein HTTP): URL-Pfad endet auf .md/.markdown/.mdx.
      def self.markdown_url?(url)
        u = url.to_s.strip
        return false if u.empty?
        return false if YoutubeTranscribe.youtube_url?(u)
        path = begin
          URI.parse(u).path.to_s
        rescue URI::InvalidURIError
          ""
        end
        path.match?(/\.(md|markdown|mdx)\z/i)
      end

      def self.applies?(item)
        item.source_url.present? && markdown_url?(item.source_url)
      end

      def process!(item, actor:)
        url = item.source_url.to_s.strip
        raise "InboxItem hat keine source_url" if url.empty?

        md = fetch_markdown(url)
        fm, body = WikiImporter.new(actor: actor).send(:parse, md)
        body = body.to_s.strip
        raise "Markdown-Datei ist leer" if body.empty?

        # H1 aus dem ROH-Markdown ziehen — parse strippt die führende H1
        # aus dem Body (kein doppelter Titel), gibt sie aber nicht zurück.
        title = derive_title(fm, md, url, item)
        ki = FileProxy.create(
          actor:     actor,
          title:     title,
          item_type: parsed_item_type(fm),
          content:   body,
          topics:    parsed_topic_slugs(fm),
          tags:      Array(fm["tags"]).reject(&:blank?),
          aliases:   Array(fm["aliases"]).reject(&:blank?)
        )
        attach_source!(ki, url, fm, actor: actor)
        record_result(item, knowledge_item: ki)
      end

      private

      def fetch_markdown(url, max_redirects: 5)
        uri = URI.parse(url)
        max_redirects.times do
          res = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https",
                                open_timeout: 5, read_timeout: 15) do |http|
            http.request(Net::HTTP::Get.new(uri,
              "User-Agent" => "miolimOS/1.0 (+md-import)",
              "Accept"     => "text/markdown, text/plain, */*"))
          end
          case res
          when Net::HTTPSuccess
            body = res.body.to_s.dup.force_encoding("UTF-8")
            raise "Datei ist kein Text (Binärinhalt)" unless body.valid_encoding?
            if body.lstrip.start_with?("<!DOCTYPE", "<!doctype", "<html", "<HTML")
              raise "URL lieferte HTML statt Markdown — dafür den Web-Clip nutzen."
            end
            return body
          when Net::HTTPRedirection
            uri = URI.parse(res["location"])
          else
            raise "HTTP #{res.code} für #{url}"
          end
        end
        raise "Zu viele Redirects für #{url}"
      end

      # Titel: Frontmatter → erste H1/H2 im Roh-MD → InboxItem-Titel →
      # Dateiname → URL.
      def derive_title(fm, md, url, item)
        t = fm["title"].presence
        t ||= (m = md.match(/^\#{1,2}\s+(.+?)\s*$/)) && m[1].strip
        t ||= item.title.presence
        t ||= File.basename(URI.parse(url).path.to_s, ".*").tr("-_", "  ").strip.presence
        (t || url).to_s.strip
      end

      def parsed_item_type(fm)
        raw = fm["type"].presence&.to_s&.downcase
        return :note unless raw
        KnowledgeItem.item_types.key?(raw) ? raw.to_sym : :note
      end

      def parsed_topic_slugs(fm)
        Array(fm["topics"]).filter_map { |t| t.to_s.strip.presence }
                           .select { |s| Topic.exists?(slug: s) }
      end

      # Provenance: die geladene URL immer als Source verknüpfen.
      def attach_source!(ki, url, fm, actor:)
        csl = fm["source_type"].presence&.to_s&.strip
        csl = "webpage" unless Source::CSL_TYPES.include?(csl)
        src = Source.find_or_create_by(url: url) do |s|
          s.title    = fm["title"].presence || ki.title
          s.csl_type = csl
          s.creator  = actor
        end
        FileProxy.merge_frontmatter!(actor: actor, knowledge_item: ki, bib_source: src.slug) if src&.slug
      end
    end
  end
end
