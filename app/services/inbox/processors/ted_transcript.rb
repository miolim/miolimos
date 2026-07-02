module Inbox
  module Processors
    # #778 (Hans, 2026-06-29): TED-Talk-URL → KI mit Metadaten + dem
    # OFFIZIELLEN TED-Transkript (aus dem __NEXT_DATA__-JSON der Seite),
    # statt das Audio neu per Whisper zu transkribieren — akkurater, gratis,
    # sofort, mit TEDs eigener Absatz-Gliederung + Zeitstempeln.
    class TedTranscript < ProcessorBase
      def self.kind        = "ted_transcript"
      def self.label       = "TED: Metadaten + offizielles Transkript"
      def self.description = "Lädt Titel/Sprecher/Beschreibung + das offizielle TED-Transkript (kein Whisper)."

      def self.applies?(item)
        ted_talk_url?(item.source_url)
      end

      def self.ted_talk_url?(url)
        url.to_s.match?(%r{\Ahttps?://(?:www\.)?ted\.com/talks/[\w%.-]+}i)
      end

      def process!(item, actor:)
        url = item.source_url.to_s.strip
        raise "InboxItem hat keine source_url" if url.empty?

        html = Inbox::Processors::WebClip.new.send(:fetch_html, url)
        data = Inbox::Ted::Transcript.extract(html)
        video = data["video"]

        link_for   = ->(sec) { "#{url}#t=#{sec}" }
        paras_md   = Inbox::Ted::Transcript.paragraphs_markdown(data["paragraphs"], link_for: link_for)
        body       = Inbox::Ted::Transcript.build_markdown(video, paras_md)
        title      = video["title"].presence || item.title.presence || url

        src = upsert_source(video, url, actor: actor)

        ki = FileProxy.create(
          actor:     actor,
          title:     title,
          item_type: :transcript,
          content:   body,
          tags:      (ted_topics(video) + ["ted"]).uniq
        )
        if src
          ki.update!(bib_source_id: src.id)
          FileProxy.merge_frontmatter!(actor: actor, knowledge_item: ki, bib_source: src.slug)
        end
        record_result(item, knowledge_item: ki)
      end

      private

      def ted_topics(video)
        nodes = video.dig("topics", "nodes")
        Array(nodes).filter_map { |n| n["name"].to_s.presence }
      end

      # Idempotenter Source-Upsert für den Talk (Slug ted-<id>), damit
      # Re-Imports dieselbe bibliografische Quelle treffen (Dubletten/Cites).
      def upsert_source(video, url, actor:)
        id = video["id"].to_s
        return nil if id.empty?
        slug     = "ted-#{id}".downcase
        raw_date = video["recordedOn"].to_s.presence || video["publishedAt"].to_s.presence
        s = Source.find_or_initialize_by(slug: slug)
        s.assign_attributes(
          csl_type:      "speech",
          title:         video["title"].to_s.presence || url,
          publisher:     "TED",
          issued_string: raw_date,
          issued_date:   (Date.parse(raw_date) if raw_date rescue nil),
          accessed:      Date.current,
          language:      video["internalLanguageCode"].to_s.presence,
          url:           video["canonicalUrl"].to_s.presence || url,
          abstract:      video["description"].to_s.presence,
          creator:       actor
        )
        s.save!
        s.source_identifiers.find_or_create_by!(scheme: "TED") { |si| si.value = id }
        # Sprecher als Person-KI mit role=author verknüpfen (idempotent).
        Inbox::SourceCreatorLink.link_person!(s, video["presenterDisplayName"].to_s.presence, actor: actor)
        s
      rescue => e
        Rails.logger.warn("TED-Source-Upsert fehlgeschlagen: #{e.class} #{e.message}")
        nil
      end
    end
  end
end
