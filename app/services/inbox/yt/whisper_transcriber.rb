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

      # #1675: Abschnitte, die sich nicht transkribieren ließen —
      # [{ abschnitt:, von:, bis: }] in Sekunden. Leer = lückenlos.
      attr_reader :luecken

      VERSUCHE = 2   # ein vorübergehender Fehler (429, Zeitüberschreitung) bekommt EINE Wiederholung

      def initialize(actor:)
        @actor    = actor
        @segments = []
        @luecken  = []
      end

      def call(url, language_hint: nil)
        result = ""
        @segments = []
        @luecken  = []
        LlmActivity.track(
          kind: :inbox_youtube_whisper, actor: @actor,
          source_kind: "url", source_id: url,
          input_summary: "Whisper-Transkription für #{url}",
          model: Llm::WhisperClient::DEFAULT_MODEL
        ) do
          duration_sec = nil
          Dir.mktmpdir("yt-audio-") do |dir|
            # #1410: KEIN `break if audio.nil?` mehr — der Download wirft
            # jetzt. Vorher wurde ein fehlgeschlagener Download zu einem
            # leeren Transkript, das als Erfolg verbucht wurde.
            audio = YtDlp.download_audio(url, dir)
            duration_sec = probe_duration(audio)

            chunks = split_if_needed(audio, dir)
            offset = 0.0   # #660: kumulierte Dauer vorheriger Chunks
            texts  = chunks.map.with_index do |chunk_path, idx|
              Rails.logger.info("Whisper: chunk #{idx + 1}/#{chunks.size} (#{File.size(chunk_path) / 1024}KB)")
              versuch = 0
              resp = begin
                versuch += 1
                Llm::WhisperClient.transcribe(path: chunk_path, language: language_hint, with_segments: true)
              rescue => e
                raise if versuch >= VERSUCHE
                Rails.logger.warn("Whisper-Chunk #{idx + 1}: Versuch #{versuch} fehlgeschlagen (#{e.class}), wiederhole")
                retry
              end
              Array(resp["segments"]).each do |seg|
                @segments << { "start" => seg["start"].to_f + offset,
                               "end"   => seg["end"].to_f + offset,
                               "text"  => seg["text"] }
              end
              resp["text"].to_s.strip
            rescue => e
              Rails.logger.warn("Whisper-Chunk #{idx + 1} fehlgeschlagen: #{e.class} #{e.message}")
              # #1675: Vorher wurde daraus still "" — bei einem langen Video
              # fehlten so 10, 40, 70 Minuten MITTEN im Transkript, ohne jede
              # Spur, als „verarbeitet" verbucht. Jetzt steht die Lücke mit ihrer
              # Zeitspanne im Text UND in der Zeitleiste; `luecken` sagt es dem
              # Aufrufer.
              bis = offset + (probe_duration(chunk_path) || CHUNK_SECONDS.to_f)
              @luecken << { abschnitt: idx + 1, von: offset, bis: bis }
              hinweis = "[… Abschnitt #{idx + 1} von #{chunks.size} (#{uhr(offset)}–#{uhr(bis)}) " \
                        "konnte nicht transkribiert werden …]"
              @segments << { "start" => offset, "end" => bis, "text" => hinweis }
              hinweis
            ensure
              # Echte Chunk-Dauer addieren (ffmpeg segmentiert an
              # Keyframes — Chunks sind ~600s, aber nicht exakt).
              offset += (probe_duration(chunk_path) || CHUNK_SECONDS.to_f)
            end
            result = texts.reject(&:blank?).join(" ").strip
            # #1410: Ein einzelner gescheiterter Chunk ist verschmerzbar — ein
            # Transkript ohne einen einzigen brauchbaren Chunk ist kein
            # Transkript. Das als Erfolg zu verbuchen war derselbe Fehler wie
            # beim Download.
            if @luecken.size == chunks.size && chunks.any?
              raise YtDlp::Error, "Whisper lieferte für keinen der #{chunks.size} Audio-Abschnitte Text"
            end
          end
          # #628 W0: Whisper kostet pro Audiominute (0,006 USD) — als
          # cost_eur an die LlmActivity, Tokens gibt es hier nicht.
          { output: result, cost_eur: whisper_cost_eur(duration_sec) }
        end
        result
      end

      private

      # #628 W0: Audiolänge via ffprobe — Basis der Whisper-Kosten.
      # Sekunden → "mm:ss" bzw. "h:mm:ss" für den Lücken-Hinweis.
      def uhr(sekunden)
        s = sekunden.to_i
        s >= 3600 ? format("%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60) : format("%d:%02d", s / 60, s % 60)
      end

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
