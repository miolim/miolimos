module Inbox
  # Registry für Processors — UI fragt diese Liste ab um den Picker zu
  # bauen. Reihenfolge entspricht Default-Anzeige.
  class Registry
    def self.all
      [
        Processors::MarkdownToKi,
        Processors::ImageToKi,      # #609 v2: Bild-Upload → Bild-KI
        Processors::PdfBibImport,
        Processors::YoutubeTranscribe,
        Processors::TedTranscript,    # #778: TED-Talk → offizielles Transkript
        Processors::MarkdownUrl,      # #799: Link auf .md-Datei → formattreue KI
        Processors::WebClip,
        Processors::AiTransform
      ]
    end

    def self.find(kind)
      all.find { |p| p.kind == kind.to_s }
    end
  end
end
