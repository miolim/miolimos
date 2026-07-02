module Inbox
  module Yt
    # Idempotenter Upsert: gleiche YT-Video-ID → gleiche Source. Slug
    # `yt-<videoid>`, damit zwei Imports desselben Videos die selbe
    # bibliographische Quelle bekommen (Citations etc.). Liefert die
    # Source oder nil, wenn Metadata keine ID hatten oder das Save
    # gescheitert ist (z.B. CSL-Validation) — der Caller toleriert nil.
    class SourceUpserter
      def self.call(meta, url, actor:)
        video_id = meta["id"].to_s
        return nil if video_id.empty?

        slug = "yt-#{video_id}".downcase
        s = Source.find_or_initialize_by(slug: slug)
        # `publisher` = Channel/Uploader (CSL-motion_picture: Studio/
        # Distributor) — der Autor des Videos in YouTube-Sicht.
        # `container_title` = Channel-URL als Backref auf den Kanal.
        s.assign_attributes(
          csl_type:        "motion_picture",
          title:           meta["title"].to_s.presence || url,
          publisher:       meta["uploader"].to_s.presence || meta["channel"].to_s.presence,
          container_title: meta["channel_url"].to_s.presence || meta["uploader_url"].to_s.presence,
          issued_string:   meta["upload_date"].to_s.presence,
          issued_date:     parse_date(meta["upload_date"]),
          accessed:        Date.current,
          language:        meta["language"].to_s.presence,
          url:             url,
          abstract:        meta["description"].to_s.presence,
          creator:         actor
        )
        s.save!
        # YouTube-Video-ID als Identifier — damit ist die Source auch
        # über die rohe Video-ID auffindbar (Suchen, Cite-Picker).
        s.source_identifiers.find_or_create_by!(scheme: "YouTube") do |si|
          si.value = video_id
        end
        # #201: Channel-Owner als Organization-KI mit role=author verknüpfen.
        # Idempotent: SourceCreatorLink macht nichts, wenn bereits Creators
        # existieren — bewahrt händische Pflege bei Re-Imports.
        channel_name = meta["uploader"].to_s.presence || meta["channel"].to_s.presence
        Inbox::SourceCreatorLink.link_organization!(s, channel_name, actor: actor)
        s
      rescue => e
        Rails.logger.warn("YT-Source-Upsert fehlgeschlagen: #{e.class} #{e.message}")
        nil
      end

      def self.parse_date(s)
        return nil if s.blank?
        Date.parse(s.to_s) rescue nil
      end
    end
  end
end
