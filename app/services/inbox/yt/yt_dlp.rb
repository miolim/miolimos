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
      # #1410: Ein Fehlschlag WIRFT. Vorher kam `nil` zurück, und die beiden
      # Transkriptions-Wege haben daraus stillschweigend ein leeres Transkript
      # gemacht — die LLM-Aktivität stand auf „erfolgreich", das Wissenselement
      # entstand ohne Text, und im Inbox-Item stand kein Wort davon. Hans sah
      # nur: kein Transkript, kein Grund. Der Grund stand ausschließlich in
      # einer Logzeile.
      #
      # Die Meldung von yt-dlp wird mitgegeben — sie sagt, ob YouTube gesperrt
      # hat, das Format fehlt oder das Netz weg war. Ohne sie beginnt die
      # Suche jedes Mal von vorn.
      def self.download_audio(url, dir)
        out_template = File.join(dir, "audio.%(ext)s")
        _out, err, status = Open3.capture3(
          BIN, "--no-warnings", "--no-playlist",
          "-f", "ba[ext=m4a]/ba[ext=webm]/bestaudio",
          "-o", out_template, url
        )
        raise Error, "yt-dlp Audio-Download fehlgeschlagen: #{fehlergrund(err)}" unless status.success?

        Dir.glob(File.join(dir, "audio.*")).find { |f| !f.end_with?(".part") } ||
          raise(Error, "yt-dlp meldete Erfolg, aber es liegt keine Audiodatei in #{dir}")
      end

      # #1410: Untertitel holen, OHNE das Video zu laden. Der Weg für Videos,
      # deren Tonspur YouTube nicht herausgibt (403/DRM) — und der billigste
      # überhaupt: kein Download, keine Transkriptionskosten.
      #
      # `json3` statt vtt, weil das Format die Zeilen einzeln und ohne die
      # Überblend-Duplikate liefert, mit denen die vtt-Fassung der
      # Auto-Untertitel jede Zeile zweimal enthält.
      def self.download_subtitles(url, dir, lang: "en")
        out_template = File.join(dir, "sub.%(ext)s")
        _out, err, status = Open3.capture3(
          BIN, "--no-warnings", "--no-playlist", "--skip-download",
          "--write-auto-subs", "--write-subs",
          "--sub-langs", lang, "--sub-format", "json3",
          "-o", out_template, url
        )
        raise Error, "yt-dlp Untertitel-Download fehlgeschlagen: #{fehlergrund(err)}" unless status.success?

        Dir.glob(File.join(dir, "sub*.json3")).first ||
          raise(Error, "Keine Untertitel-Datei für Sprache #{lang} erhalten")
      end

      # Die erste Zeile von yt-dlp ist oft ein Fortschrittsbalken; die
      # brauchbare Auskunft steht in der ERROR-Zeile.
      def self.fehlergrund(stderr)
        zeilen = stderr.to_s.lines.map(&:strip).reject(&:empty?)
        (zeilen.find { |l| l.start_with?("ERROR") } || zeilen.last || "kein Grund gemeldet")
          .truncate(300)
      end
    end
  end
end
