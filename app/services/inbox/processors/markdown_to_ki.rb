module Inbox
  module Processors
    # Verarbeitet ein InboxItem mit raw_content (oder externer Datei),
    # das eine Markdown-Notiz darstellt.
    #
    # #307 (Hans, 2026-05-23): Versionierung (append_to/chat_title-
    # Match → append_session) ausgebaut — jeder Import landet als
    # neue KI. MD ohne Frontmatter? Kein Problem, item_type defaultet
    # auf :note und Title kommt aus dem Filename.
    #
    # #307 follow-up (Hans, 2026-05-24): explizite Frontmatter-
    # Konvention. Erlaubte Keys werden interpretiert, alles andere
    # ignoriert (Log-Eintrag). Source-Auto-Resolve ueber bib_source
    # (Slug) oder source_url; Source wird bei Bedarf angelegt
    # (csl_type = `source_type` oder `webpage`). Title-Dubletten:
    # Auto-Skip mit Warnung, ausser Frontmatter setzt
    # `force_create: true`.
    class MarkdownToKi < ProcessorBase
      def self.kind        = "markdown_to_ki"
      def self.label       = "Als Wissens-KI anlegen"
      def self.description = "Markdown-Notiz anlegen. Frontmatter (title/type/source_url/bib_source/topics/tags/aliases) wird interpretiert; alles andere ignoriert."

      ALLOWED_KEYS = %w[
        title type source_url source_type bib_source
        topics tags aliases
        started_at ended_at force_create chat_title
      ].freeze

      def self.applies?(item)
        # #609 v2: Bild-Uploads gehören zu ImageToKi — der Markdown-Pfad
        # würde das Binärfile als Text lesen (invalid byte sequence).
        return false if item.source_kind == "upload" && ImageToKi.image?(item)
        item.source_kind.in?(%w[markdown text upload]) ||
          (item.source_kind == "web_url" && item.raw_content.present?)
      end

      def process!(item, actor:)
        raw = read_raw(item)
        importer = WikiImporter.new(actor: actor)
        fm, body = importer.send(:parse, raw)

        title = derive_title(fm, item)
        raise "Title fehlt — bitte Frontmatter `title:` setzen oder InboxItem.title pflegen" if title.empty?

        if dup_exists?(title) && fm["force_create"].to_s != "true"
          raise "Notiz mit Titel \"#{title}\" existiert bereits. Frontmatter `force_create: true` setzen, um trotzdem anzulegen."
        end

        log_ignored_keys(fm)

        ki = FileProxy.create(
          actor:     actor,
          title:     title,
          item_type: parsed_item_type(fm),
          content:   body.strip,
          topics:    parsed_topic_slugs(fm),
          tags:      Array(fm["tags"]).reject(&:blank?),
          aliases:   Array(fm["aliases"]).reject(&:blank?)
        )

        attach_source!(ki, fm, actor: actor)

        record_result(item, knowledge_item: ki)
      end

      private

      def derive_title(fm, item)
        (fm["title"].presence ||
         fm["chat_title"].presence ||
         item.title.presence ||
         item.display_title.presence ||
         "(Inbox-Import #{Date.current.iso8601})").to_s.strip
      end

      def dup_exists?(title)
        KnowledgeItem.where(deleted_at: nil)
                     .where("LOWER(title) = ?", title.downcase)
                     .exists?
      end

      def parsed_item_type(fm)
        raw = fm["type"].presence&.to_s&.downcase
        return :note unless raw
        KnowledgeItem.item_types.key?(raw) ? raw.to_sym : :note
      end

      def parsed_topic_slugs(fm)
        slugs = Array(fm["topics"]).filter_map { |t| t.to_s.strip.presence }
        slugs.select do |slug|
          if Topic.exists?(slug: slug)
            true
          else
            Rails.logger.info("MarkdownToKi: Topic-Slug '#{slug}' existiert nicht — uebersprungen")
            false
          end
        end
      end

      # Source-Resolve: erst bib_source-Slug (exakter Match), dann
      # source_url (find_or_create). source_type vom Frontmatter kann
      # csl_type vorgeben, default `webpage`.
      def attach_source!(ki, fm, actor:)
        source = resolve_source(fm)
        return unless source
        FileProxy.merge_frontmatter!(actor: actor, knowledge_item: ki, bib_source: source.slug)
      end

      def resolve_source(fm)
        if (slug = fm["bib_source"].presence&.to_s&.strip)
          src = Source.find_by(slug: slug)
          Rails.logger.warn("MarkdownToKi: bib_source-Slug '#{slug}' nicht gefunden") unless src
          return src
        end
        url = fm["source_url"].presence&.to_s&.strip
        return nil unless url
        csl_type = fm["source_type"].presence&.to_s&.strip
        csl_type = "webpage" unless Source::CSL_TYPES.include?(csl_type)
        Source.find_or_create_by(url: url) do |s|
          s.title    = fm["title"].presence || url
          s.csl_type = csl_type
        end
      end

      def log_ignored_keys(fm)
        ignored = (fm.keys.map(&:to_s) - ALLOWED_KEYS).reject(&:blank?)
        return if ignored.empty?
        Rails.logger.info("MarkdownToKi: ignorierte Frontmatter-Keys: #{ignored.inspect}")
      end

      def read_raw(item)
        raw =
          if item.raw_content.present?
            item.raw_content
          elsif item.external_path.present? && File.exist?(item.external_path)
            File.read(item.external_path)
          else
            raise "InboxItem hat weder raw_content noch external_path"
          end
        # #609 v2: Binärdateien klar abweisen statt spaeter kryptisch an
        # "invalid byte sequence in UTF-8" zu sterben.
        raw = raw.dup.force_encoding(Encoding::UTF_8)
        unless raw.valid_encoding?
          raise "Datei ist keine Text-/Markdown-Datei (Binärinhalt) — für Bilder den Processor \"Als Bild-KI anlegen\" verwenden."
        end
        raw
      end
    end
  end
end
