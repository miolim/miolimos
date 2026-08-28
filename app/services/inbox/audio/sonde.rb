require "open3"
require "json"

module Inbox
  module Audio
    # #1492 (Hans): „Den MP3-Weg ergänzen."
    #
    # Für eine Audio-Adresse gibt es keine Metadaten-Schnittstelle wie bei
    # YouTube. Was es gibt, steht in der Datei selbst — und `ffprobe` liest
    # den Kopf einer Fern-Datei, ohne sie zu laden: Für die 68-MB-Folge des
    # Podcasts kam die Dauer in 0,35 Sekunden zurück.
    #
    # Das ist wichtiger als es klingt: Die Dauer entscheidet über die
    # Kostenschätzung, und die steht VOR der Bestätigung. Müsste man dafür
    # erst herunterladen, wäre die Reihenfolge „erst zahlen, dann fragen".
    #
    # Zurück kommt ein Hash in derselben Form, die die yt-dlp-Metadaten
    # haben — damit die vorhandenen Helfer (MarkdownBuilder, SourceUpserter,
    # TranscriptPostProcessor) unverändert weiterarbeiten.
    class Sonde
      class Error < StandardError; end

      # Als Methode, nicht als Konstante: Eine Konstante steht beim Laden
      # der Klasse fest, und dann laesst sich im Test kein Doppelgaenger
      # unterschieben, ohne die Klasse selbst zu verbiegen.
      def self.bin = ENV["FFPROBE_BIN"].presence || "ffprobe"

      # ID3/MP4-Felder heissen je nach Container anders. Die Reihenfolge
      # ist die Rangfolge: Was zuerst da ist, gewinnt.
      TITEL_FELDER  = %w[title TITLE Title].freeze
      AUTOR_FELDER  = %w[artist ARTIST album_artist album ALBUM].freeze
      DATUM_FELDER  = %w[date DATE creation_time year].freeze
      TEXT_FELDER   = %w[comment description synopsis].freeze

      def self.call(url, fallback_title: nil)
        new(url).call(fallback_title: fallback_title)
      end

      def initialize(url)
        @url = url.to_s.strip
      end

      def call(fallback_title: nil)
        format = probe.fetch("format", {})
        tags   = format.fetch("tags", {})

        {
          "title"       => tag(tags, TITEL_FELDER).presence || fallback_title.presence || dateiname,
          "duration"    => format["duration"].to_f.round,
          "uploader"    => tag(tags, AUTOR_FELDER).presence,
          "upload_date" => datum(tag(tags, DATUM_FELDER)),
          "description" => beschreibung(tag(tags, TEXT_FELDER)),
          "webpage_url" => @url,
          # Bewusst leer: Eine Audiodatei sagt nichts über ihre Sprache.
          # Whisper erkennt sie dann selbst — besser als ein falscher Hinweis,
          # der aus Englisch eine deutsche Übersetzung machen würde (#660).
          "language"    => nil,
          "tags"        => []
        }
      end

      private

      def probe
        @probe ||= begin
          out, err, status = Open3.capture3(self.class.bin, "-v", "quiet", "-print_format", "json",
                                            "-show_format", @url)
          unless status.success?
            raise Error, "ffprobe konnte #{@url} nicht lesen: #{err.to_s.lines.first&.strip}"
          end
          JSON.parse(out.presence || "{}")
        rescue JSON::ParserError => e
          raise Error, "ffprobe lieferte kein lesbares JSON: #{e.message}"
        end
      end

      def tag(tags, felder)
        felder.filter_map { |f| tags[f].presence }.first
      end

      # Im `comment`-Feld steht oft kein Text, sondern eine Container-Notiz
      # des Schnittprogramms — bei der Podcast-Folge stand dort schlicht
      # „Bwf". Als Beschreibung im Wissenselement waere das Rauschen.
      # Deshalb: erst ab einer Laenge, die nach einem Satz aussieht.
      BESCHREIBUNG_MIN = 40

      def beschreibung(wert)
        w = wert.to_s.strip
        w.length >= BESCHREIBUNG_MIN ? w : nil
      end

      # yt-dlp liefert `upload_date` als "YYYYMMDD"; MarkdownBuilder.format_date
      # erwartet genau das. Aus "2026-07-24" oder "2026-07-24T10:00:00Z" wird
      # hier dasselbe Format, aus Unbrauchbarem nichts.
      def datum(wert)
        return nil if wert.blank?
        Date.parse(wert.to_s).strftime("%Y%m%d")
      rescue Date::Error
        nil
      end

      def dateiname
        pfad = URI.parse(@url).path.to_s
        name = File.basename(pfad, ".*")
        name.presence || @url
      rescue URI::InvalidURIError
        @url
      end
    end
  end
end
