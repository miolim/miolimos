require "open3"
require "json"

module Inbox
  module Yt
    # Wrapper um die yt-dlp-CLI: Binary-Lookup und die zwei Aufrufe,
    # die der YT-Processor heute braucht (Metadata-JSON + Audio-Download
    # ohne Re-Encoding). Subprozesse ausschließlich an dieser Stelle —
    # erleichtert das Stubben in Tests.
    class YtDlp
      class Error < StandardError; end

      # yt-dlp wird oft per `pip install --user` installiert (~/.local/bin),
      # was nicht im systemd-Default-PATH liegt. Reihenfolge:
      # ENV-Override → ~/.local/bin/yt-dlp → /usr/local/bin/yt-dlp → "yt-dlp".
      BIN = begin
        if (env = ENV["YT_DLP_BIN"]).present? && File.executable?(env)
          env
        elsif File.executable?(File.expand_path("~/.local/bin/yt-dlp"))
          File.expand_path("~/.local/bin/yt-dlp")
        elsif File.executable?("/usr/local/bin/yt-dlp")
          "/usr/local/bin/yt-dlp"
        else
          "yt-dlp"
        end
      end

      def self.fetch_metadata(url)
        out, err, status = Open3.capture3(BIN, "--dump-single-json", "--no-playlist",
                                           "--no-warnings", url)
        raise Error, "yt-dlp metadata failed: #{err.lines.first}" unless status.success?
        JSON.parse(out)
      end

      # Lädt den kleinsten m4a/webm-only-Stream und liefert den Pfad
      # zur Audio-Datei in `dir`. Whisper akzeptiert m4a/webm direkt —
      # kein ffmpeg-Transcode nötig (das hat bei 30-min-Audios ~5 min
      # CPU gefressen).
      def self.download_audio(url, dir)
        out_template = File.join(dir, "audio.%(ext)s")
        _out, err, status = Open3.capture3(
          BIN, "--no-warnings", "--no-playlist",
          "-f", "ba[ext=m4a]/ba[ext=webm]/bestaudio",
          "-o", out_template, url
        )
        unless status.success?
          Rails.logger.warn("yt-dlp audio-download fehlgeschlagen: #{err.lines.first}")
          return nil
        end
        Dir.glob(File.join(dir, "audio.*")).find { |f| !f.end_with?(".part") }
      end
    end
  end
end
