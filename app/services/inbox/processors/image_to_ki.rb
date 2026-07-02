module Inbox
  module Processors
    # #609 v2 (Hans, 2026-06-12): Bilddatei aus der Inbox als Bild-KI
    # übernehmen — vorher griff der Markdown-Processor und las das
    # Binärfile als Text ("invalid byte sequence in UTF-8"). Nutzt
    # denselben Pfad wie der Paste-Upload (FileProxy.create_with_file),
    # das Ergebnis ist via ![[Titel]] einbettbar.
    class ImageToKi < ProcessorBase
      def self.kind        = "image_to_ki"
      def self.label       = "Als Bild-KI anlegen"
      def self.description = "Bilddatei als Bild-KI übernehmen — einbettbar über ![[Titel]]."

      IMAGE_EXT = /\.(png|jpe?g|gif|webp|heic|svg|bmp|tiff?)\z/i

      def self.applies?(item)
        item.source_kind == "upload" && image?(item)
      end

      def self.image?(item)
        return true if item.payload["content_type"].to_s.start_with?("image/")
        item.external_path.to_s.match?(IMAGE_EXT) ||
          item.payload["original_filename"].to_s.match?(IMAGE_EXT)
      end

      def process!(item, actor:)
        path = item.external_path.to_s
        raise "Bilddatei nicht gefunden: #{path}" unless File.exist?(path)

        base  = item.display_title.presence || "Bild #{Time.current.strftime('%Y-%m-%d %H.%M.%S')}"
        title = base
        n = 2
        while KnowledgeItem.by_title_ci(title).exists?
          title = "#{base} (#{n})"
          n += 1
        end

        ki = File.open(path, "rb") do |io|
          FileProxy.create_with_file(actor: actor, title: title,
                                     uploaded_io: io, item_type: :image)   # #609 v3
        end

        inherit_topics_to_ki(ki, item)
        record_result(item, knowledge_item: ki)
        ki
      end
    end
  end
end
