require "open3"

module Inbox
  module Processors
    # Citavi-Workflow (#65): PDF wird in die Inbox hochgeladen; via
    # `Inbox::Bib::Pipeline` werden in Reihenfolge DOI/CrossRef, ISBN/
    # OpenLibrary, eingebettete /Info-Metadaten, AI-Klassifikation und
    # zuletzt der Dateiname probiert. Aus dem ersten erfolgreichen
    # Ergebnis legen wir eine neue `Source` plus ein KI vom Typ
    # `:transcript` mit der PDF-Datei selbst an.
    class PdfBibImport < ProcessorBase
      def self.kind        = "pdf_bib_import"
      def self.label       = "PDF → Source + KI (Citavi)"
      def self.description = "Extrahiert bibliografische Daten (DOI, ISBN, /Info, AI, Filename) und legt Source + PDF-KI an."

      def self.applies?(item)
        item.source_kind == "pdf_upload"
      end

      # `pdftotext` als Klassenmethode, damit Tests es bequem stubben
      # können (gleiche Pattern wie Inbox::Yt::YtDlp).
      def self.extract_first_pages(path)
        out, _err, status = Open3.capture3("pdftotext", "-l", "5", path, "-")
        raise "pdftotext (exit #{status.exitstatus}) für #{path}" unless status.success?
        out.to_s
      end

      def process!(item, actor:)
        path = item.external_path.to_s
        raise "PDF-Pfad fehlt am InboxItem" if path.empty?
        raise "PDF-Datei nicht gefunden: #{path}" unless File.exist?(path)

        text   = self.class.extract_first_pages(path)
        result = Inbox::Bib::Pipeline.call(item: item, path: path, text: text)
        raise "Keine bibliografischen Daten aus DOI/ISBN/PDF-Metadata/AI/Filename ermittelbar." if result.blank?

        existing      = Inbox::Bib::SourceMatcher.find(result)
        source        = existing || create_source(result, actor: actor)
        ki            = create_transcript_ki(item, source, actor: actor)

        item.update_column(:result, item.result.merge(
          "source"      => { "slug" => source.slug, "reused" => existing.present? },
          "provenance"  => result[:provenance]
        ))
        record_result(item, knowledge_item: ki)
      end

      private

      # Neue Source komplett anlegen — wird NUR aufgerufen, wenn der
      # Matcher keine bestehende gefunden hat. Bestehende Sources
      # werden bewusst nicht überschrieben, weil der User sie händisch
      # gepflegt haben könnte; wir hängen nur ein weiteres KI dran.
      def create_source(result, actor:)
        source = Source.new(slug: build_slug(result))
        source.assign_attributes(
          csl_type:        result[:csl_type].presence || "article-journal",
          title:           result[:title].to_s.strip.presence || "Untitled",
          container_title: result[:container_title].presence,
          publisher:       result[:publisher].presence,
          publisher_place: result[:publisher_place].presence,
          issued_date:     result[:issued_date],
          issued_string:   result[:issued_string].presence,
          volume:          result[:volume].presence,
          issue:           result[:issue].presence,
          pages:           result[:pages].presence,
          abstract:        result[:abstract].presence,
          language:        result[:language].presence,
          url:             result[:url].presence,
          accessed:        Date.current,
          creator:         actor
        )
        source.save!

        if (ident = result[:identifier]) && ident[:value].to_s.strip.present?
          source.source_identifiers.create!(scheme: ident[:scheme], value: ident[:value])
        end
        sync_creators!(source, result[:authors], actor: actor)
        source
      end

      # Creators nur beim Erstanlegen befüllen — Re-Import soll
      # bestehende Reihenfolge nicht durcheinanderwürfeln.
      def sync_creators!(source, authors, actor:)
        return if source.source_creators.exists?
        Array(authors).each_with_index do |a, idx|
          ki = find_or_create_author(a[:given] || a["given"], a[:family] || a["family"], actor: actor)
          next unless ki
          source.source_creators.create!(knowledge_item_uuid: ki.uuid, role: "author", position: idx)
        end
      end

      def find_or_create_author(given, family, actor:)
        given  = given.to_s.strip
        family = family.to_s.strip
        title  = [given, family].reject(&:blank?).join(" ")
        return nil if title.empty?
        if (existing = KnowledgeItem.persons.by_title_ci(title).first)
          return existing
        end
        ki = FileProxy.create(actor: actor, title: title, item_type: :person, content: "")
        ki.update!(first_name: given.presence, last_name: family.presence)
        ki
      end

      # Citavi-Stil "doe-2024-climate"; bei fehlender Author/Year/Title-
      # Basis fällt's auf Identifier ("doi-…") oder Title-Parameterize zurück.
      def build_slug(result)
        family = Array(result[:authors]).first&.dig(:family).to_s
        family = Array(result[:authors]).first&.dig("family").to_s if family.blank?
        family = family.parameterize
        year   = (result[:issued_date]&.year || result[:issued_string].to_s.scan(/\d{4}/).first).to_s
        title_word = result[:title].to_s
                      .split(/\s+/)
                      .find { |w| w.length > 3 && w !~ /\A(the|der|die|das|and|of|on|in|for|with|als|und|von|une|les)\z/i }
                      .to_s.parameterize
        parts = [family, year, title_word].reject(&:blank?)
        base  =
          if parts.any?                     then parts.join("-")
          elsif result[:identifier].present? then "#{result[:identifier][:scheme].downcase}-#{result[:identifier][:value].to_s.parameterize}"
          else                                  result[:title].to_s.parameterize.presence || "source-#{SecureRandom.hex(3)}"
          end
        slug = base
        i = 2
        while Source.exists?(slug: slug)
          slug = "#{base}-#{i}"
          i += 1
        end
        slug
      end

      def create_transcript_ki(item, source, actor:)
        title = source.title.presence || item.display_title
        File.open(item.external_path, "rb") do |io|
          ki = FileProxy.create_with_file(
            actor:       actor,
            title:       title,
            uploaded_io: io,
            item_type:   :transcript
          )
          ki.update!(bib_source_id: source.id)
          FileProxy.merge_frontmatter!(actor: actor, knowledge_item: ki,
                                        bib_source: source.slug)
          ki.reload
        end
      end
    end
  end
end
