require "net/http"
require "json"
require "uri"

# Embedding-Service über Ollama (http://localhost:11434).
# Erwartet, dass `ollama pull bge-m3` einmalig gelaufen ist.
#
# Nutzung:
#   vec = Classifiers::OllamaEmbedder.new.embed("Text")
#   vec.length  # -> 1024 bei bge-m3
#
# Wenn Ollama nicht läuft, gibt .embed nil zurück und der Aufrufer
# muss das graceful behandeln (kein Crash im Sync).
module Classifiers
  class OllamaEmbedder
    DEFAULT_HOST  = ENV.fetch("OLLAMA_HOST",  "http://localhost:11434")
    DEFAULT_MODEL = ENV.fetch("OLLAMA_EMBED_MODEL", "bge-m3")

    class UnavailableError < StandardError; end

    def initialize(host: DEFAULT_HOST, model: DEFAULT_MODEL, read_timeout: 20)
      @host = host
      @model = model
      @read_timeout = read_timeout
    end

    # Liefert ein Float-Array oder nil bei Fehler.
    def embed(text)
      return nil if text.blank?
      # Gmail-Bodies kommen teils als BINARY-String mit UTF-8-Bytes an —
      # JSON.generate warnt darauf (und wirft ab json 3.0). Bytes als UTF-8
      # deklarieren und Invalides ersetzen statt platzen.
      prompt = text.to_s
      prompt = prompt.dup.force_encoding(Encoding::UTF_8) unless prompt.encoding == Encoding::UTF_8
      prompt = prompt.scrub("�")
      body = JSON.generate({ model: @model, prompt: prompt })
      uri  = URI("#{@host}/api/embeddings")

      Net::HTTP.start(uri.host, uri.port, read_timeout: @read_timeout, open_timeout: 2) do |http|
        req = Net::HTTP::Post.new(uri.path, "Content-Type" => "application/json")
        req.body = body
        res = http.request(req)
        raise UnavailableError, "Ollama HTTP #{res.code}: #{res.body.to_s.truncate(200)}" unless res.is_a?(Net::HTTPSuccess)

        parsed = JSON.parse(res.body)
        parsed["embedding"] || parsed["embeddings"]&.first
      end
    rescue Errno::ECONNREFUSED, Net::OpenTimeout, Net::ReadTimeout, UnavailableError, JSON::ParserError => e
      Rails.logger.warn("OllamaEmbedder: #{e.class} #{e.message}")
      nil
    end

    def available?
      uri = URI("#{@host}/api/tags")
      Net::HTTP.start(uri.host, uri.port, open_timeout: 2) do |http|
        http.request(Net::HTTP::Get.new(uri.path)).is_a?(Net::HTTPSuccess)
      end
    rescue StandardError
      false
    end
  end
end
