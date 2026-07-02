require "net/http"
require "json"
require "uri"
require "securerandom"

module Llm
  # Audio-Transkription via OpenAI Whisper API.
  #
  # Key kommt aus ENV["OPENAI_API_KEY"] oder credentials[:openai][:api_key].
  # Datei-Limit der API: 25 MB pro Request — größere Files muss der Caller
  # vorher in Chunks splitten (siehe Inbox::Processors::YoutubeTranscribe).
  module WhisperClient
    class UnavailableError < StandardError; end

    DEFAULT_MODEL  = ENV.fetch("OPENAI_WHISPER_MODEL", "whisper-1")
    USD_PER_MINUTE = 0.006
    USD_TO_EUR     = 0.93

    def self.api_key
      ENV["OPENAI_API_KEY"].presence ||
        Rails.application.credentials.dig(:openai, :api_key).presence
    end

    def self.available?
      api_key.present?
    end

    # Transkribiert eine Audio-Datei. `path` muss Pfad zu lokaler Datei sein,
    # `language` ISO-639-1 ("de", "en") oder nil für Auto-Detect.
    #
    # Default: Plain-Text-String (Rückwärtskompatibel).
    # `with_segments: true` (#660): liefert ein Hash
    #   { "text" => "…", "segments" => [{ "start" =>, "end" =>, "text" => }, …] }
    # über `response_format=verbose_json` — selber API-Call, gleiche Kosten,
    # zusätzlich die Zeitstempel pro Segment.
    def self.transcribe(path:, language: nil, model: DEFAULT_MODEL, prompt: nil, with_segments: false)
      raise UnavailableError, "OPENAI_API_KEY nicht gesetzt" unless available?
      raise "Datei nicht gefunden: #{path}" unless File.exist?(path)

      boundary = "----miolimos-#{SecureRandom.hex(12)}"
      body = build_multipart(boundary,
        file_path: path,
        fields: {
          "model"           => model,
          "response_format" => (with_segments ? "verbose_json" : "text")
        }.merge(language ? { "language" => language } : {})
         .merge(prompt.present? ? { "prompt" => prompt.to_s } : {})
      )

      uri = URI("https://api.openai.com/v1/audio/transcriptions")
      Net::HTTP.start(uri.host, uri.port, use_ssl: true,
                      open_timeout: 5, read_timeout: 300) do |http|
        req = Net::HTTP::Post.new(uri.path,
          "Authorization" => "Bearer #{api_key}",
          "Content-Type"  => "multipart/form-data; boundary=#{boundary}"
        )
        req.body = body
        res = http.request(req)
        raise UnavailableError, "Whisper HTTP #{res.code}: #{res.body.to_s.truncate(200)}" unless res.is_a?(Net::HTTPSuccess)
        # Whisper liefert UTF-8-Text, Net::HTTP markiert response.body aber
        # als ASCII-8BIT — ohne force_encoding kollidiert der String später
        # beim join mit UTF-8-Markdown-Headern (Encoding::CompatibilityError).
        raw = res.body.to_s.force_encoding("UTF-8")
        return raw.strip unless with_segments
        parse_verbose_json(raw)
      end
    end

    # #660: verbose_json → { "text" =>, "segments" => [{start,end,text}] }.
    # Defensiv: bei kaputtem JSON liefern wir wenigstens Rohtext ohne
    # Segmente, damit der Caller auf den strukturierten Pfad zurückfällt.
    def self.parse_verbose_json(raw)
      data = JSON.parse(raw)
      segments = Array(data["segments"]).map do |s|
        { "start" => s["start"].to_f, "end" => s["end"].to_f, "text" => s["text"].to_s }
      end
      { "text" => data["text"].to_s.strip, "segments" => segments }
    rescue JSON::ParserError
      { "text" => raw.strip, "segments" => [] }
    end

    def self.estimated_eur(seconds)
      minutes = seconds.to_f / 60.0
      (minutes * USD_PER_MINUTE * USD_TO_EUR).round(2)
    end

    def self.mime_type(path)
      case File.extname(path).downcase
      when ".mp3"  then "audio/mpeg"
      when ".m4a"  then "audio/mp4"
      when ".opus" then "audio/ogg"
      when ".ogg"  then "audio/ogg"
      when ".wav"  then "audio/wav"
      when ".webm" then "audio/webm"
      else "application/octet-stream"
      end
    end

    # Multipart-Body manuell zusammenbauen — vermeidet zusätzliche gems
    # (`multipart-post`, `faraday-multipart`). Alle String-Anteile werden
    # als ASCII-8BIT (binary) gehängt, damit binäre File-Bytes und
    # UTF-8-Header-Strings nicht kollidieren (Encoding::CompatibilityError).
    def self.build_multipart(boundary, file_path:, fields:)
      crlf = "\r\n".b
      io = String.new(encoding: "ASCII-8BIT")
      fields.each do |name, value|
        io << "--#{boundary}#{crlf}".b
        io << %(Content-Disposition: form-data; name="#{name}"#{crlf}).b
        io << crlf
        io << value.to_s.b
        io << crlf
      end
      io << "--#{boundary}#{crlf}".b
      io << %(Content-Disposition: form-data; name="file"; filename="#{File.basename(file_path)}"#{crlf}).b
      io << "Content-Type: #{mime_type(file_path)}#{crlf}".b
      io << crlf
      io << File.binread(file_path)
      io << crlf
      io << "--#{boundary}--#{crlf}".b
      io
    end
  end
end
