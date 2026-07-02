require "open3"
require "tmpdir"

module Inbox
  module Yt
    # Audio von yt-dlp ziehen, bei > 24 MB in 10-Min-Chunks splitten,
    # jeden Chunk durch Whisper schicken, Texte konkatenieren. LlmActivity
    # wird via track angelegt — wenn irgendwas hochgeht, bleibt sie als
    # `failed` stehen und der Caller bekommt "" zurück (er stört sich
    # nicht an leerem Transkript).
    class WhisperTranscriber
      WHISPER_LIMIT_MB = 24.0
      CHUNK_SECONDS    = 600

      # #660: nach `call` enthält dies die Segmente mit ABSOLUTEN
      # Sekunden (über Chunk-Grenzen hinweg) — Basis für Zeitstempel.
      attr_reader :segments

      def initialize(actor:)
        @actor    = actor
        @segments = []
      end

      def call(url, language_hint: nil)
        result = ""
        @segments = []
        LlmActivity.track(
          kind: :inbox_youtube_whisper, actor: @actor,
          source_kind: "url", source_id: url,
          input_summary: "Whisper-Transkription für #{url}",
          model: Llm::WhisperClient::DEFAULT_MODEL
        ) do
          duration_sec = nil
          Dir.mktmpdir("yt-audio-") do |dir|
            audio = YtDlp.download_audio(url, dir)
            break if audio.nil?
            duration_sec = probe_duration(audio)

            chunks = split_if_needed(audio, dir)
            offset = 0.0   # #660: kumulierte Dauer vorheriger Chunks
            texts  = chunks.map.with_index do |chunk_path, idx|
              Rails.logger.info("Whisper: chunk #{idx + 1}/#{chunks.size} (#{File.size(chunk_path) / 1024}KB)")
              resp = Llm::WhisperClient.transcribe(path: chunk_path, language: language_hint, with_segments: true)
              Array(resp["segments"]).each do |seg|
                @segments << { "start" => seg["start"].to_f + offset,
                               "end"   => seg["end"].to_f + offset,
                               "text"  => seg["text"] }
              end
              resp["text"].to_s.strip
            rescue => e
              Rails.logger.warn("Whisper-Chunk #{idx + 1} fehlgeschlagen: #{e.class} #{e.message}")
              ""
            ensure
              # Echte Chunk-Dauer addieren (ffmpeg segmentiert an
              # Keyframes — Chunks sind ~600s, aber nicht exakt).
              offset += (probe_duration(chunk_path) || CHUNK_SECONDS.to_f)
            end
            result = texts.reject(&:blank?).join(" ").strip
          end
          # #628 W0: Whisper kostet pro Audiominute (0,006 USD) — als
          # cost_eur an die LlmActivity, Tokens gibt es hier nicht.
          { output: result, cost_eur: whisper_cost_eur(duration_sec) }
        end
        result
      rescue => e
        Rails.logger.warn("Whisper-Transkription gesamt fehlgeschlagen: #{e.class} #{e.message}")
        result
      end

      private

      # #628 W0: Audiolänge via ffprobe — Basis der Whisper-Kosten.
      def probe_duration(audio_path)
        out, _err, status = Open3.capture3(
          "ffprobe", "-v", "error", "-show_entries", "format=duration",
          "-of", "csv=p=0", audio_path
        )
        status.success? ? out.to_f : nil
      rescue => e
        Rails.logger.warn("ffprobe fehlgeschlagen: #{e.class} #{e.message}")
        nil
      end

      WHISPER_USD_PER_MIN = 0.006

      def whisper_cost_eur(duration_sec)
        return nil unless duration_sec&.positive?
        (duration_sec / 60.0 * WHISPER_USD_PER_MIN * Llm::ChatClient::USD_EUR_RATE).round(6)
      end

      # Splittet, wenn Datei > 24 MB (Whisper-Limit 25 MB). ffmpeg mit
      # `-c copy` segmentiert an Frame-Grenzen — Whisper kommt damit klar.
      def split_if_needed(audio_path, dir)
        size_mb = File.size(audio_path).to_f / (1024 * 1024)
        return [audio_path] if size_mb < WHISPER_LIMIT_MB

        ext     = File.extname(audio_path).delete(".")
        pattern = File.join(dir, "chunk_%03d.#{ext}")
        _out, err, status = Open3.capture3(
          "ffmpeg", "-hide_banner", "-loglevel", "error",
          "-i", audio_path,
          "-f", "segment", "-segment_time", CHUNK_SECONDS.to_s,
          "-c", "copy", pattern
        )
        unless status.success?
          Rails.logger.warn("ffmpeg-Split fehlgeschlagen: #{err.lines.first}")
          return [audio_path]
        end
        Dir.glob(File.join(dir, "chunk_*.#{ext}")).sort
      end
    end
  end
end
