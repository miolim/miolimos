require "net/http"
require "json"
require "uri"

module Llm
  # Schmaler Chat-Completion-Client. Auto-Detection in Reihenfolge:
  #   1. ANTHROPIC_API_KEY gesetzt → Anthropic-Client (Claude)
  #   2. Ollama erreichbar mit Chat-Modell → Ollama-Client
  #   3. raise UnavailableError
  #
  # Nutzung:
  #   resp = Llm::ChatClient.complete(
  #     prompt: "Fasse diesen Text zusammen: …",
  #     model:  "ollama:llama3.1:8b"  # optional Override
  #   )
  module ChatClient
    class UnavailableError < StandardError; end

    DEFAULT_OLLAMA_HOST  = ENV.fetch("OLLAMA_HOST", "http://localhost:11434")
    DEFAULT_OLLAMA_MODEL = ENV.fetch("OLLAMA_CHAT_MODEL", "llama3.1:8b")
    DEFAULT_ANTHROPIC_MODEL = ENV.fetch("ANTHROPIC_MODEL", "claude-haiku-4-5")

    # #628 W0: Preise (USD pro 1M Tokens, [input, output]) für die
    # Kosten-Spalte an LlmActivity. Regex-Match auf den Modellnamen;
    # unbekanntes Modell → Tokens ja, Kosten nil (ehrlicher als raten).
    PRICES_USD_PER_MTOK = {
      /haiku-4/  => [1.0, 5.0],
      /haiku-3/  => [0.8, 4.0],
      /sonnet-4/ => [3.0, 15.0],
      /opus-4/   => [5.0, 25.0],
    }.freeze
    USD_EUR_RATE = ENV.fetch("USD_EUR_RATE", "0.86").to_f

    # #628 W0: Tokens + Kosten aus der Anthropic-Usage-Antwort direkt an
    # die LlmActivity schreiben (mark_succeeded! lässt vorhandene Werte
    # stehen). Fehler hier dürfen den eigentlichen Call nie reißen.
    def self.record_usage(activity, model, usage)
      return unless activity.respond_to?(:update!) && usage.is_a?(Hash)
      input  = usage["input_tokens"].to_i
      output = usage["output_tokens"].to_i
      _, prices = PRICES_USD_PER_MTOK.find { |re, _| model.to_s.match?(re) }
      cost = prices && (((input * prices[0]) + (output * prices[1])) / 1_000_000.0 * USD_EUR_RATE)
      activity.update!(input_tokens: input, output_tokens: output,
                       cost_eur: cost&.round(6))
    rescue => e
      Rails.logger.warn("ChatClient.record_usage fehlgeschlagen: #{e.class} #{e.message}")
    end

    def self.anthropic_api_key
      ENV["ANTHROPIC_API_KEY"].presence ||
        Rails.application.credentials.dig(:anthropic, :api_key).presence
    end

    # #628 W0: optionales `activity:` (LlmActivity) — der Anthropic-Pfad
    # schreibt input/output_tokens + cost_eur daran. Ollama ist lokal
    # (Kosten 0, keine Usage-Erfassung).
    def self.complete(prompt:, model: nil, system: nil, max_tokens: 2048, activity: nil)
      provider, model_name = parse_model(model)
      provider ||= detect_provider
      raise UnavailableError, "Kein LLM-Client verfügbar (Ollama läuft nicht, ANTHROPIC_API_KEY fehlt)" unless provider

      case provider
      when :anthropic
        Anthropic.new.complete(prompt: prompt, model: model_name || DEFAULT_ANTHROPIC_MODEL,
                                system: system, max_tokens: max_tokens, activity: activity)
      when :ollama
        Ollama.new.complete(prompt: prompt, model: model_name || DEFAULT_OLLAMA_MODEL,
                             system: system)
      end
    end

    def self.parse_model(model)
      return [nil, nil] if model.blank?
      provider, name = model.split(":", 2)
      [provider&.to_sym, name]
    end

    def self.detect_provider
      return :anthropic if anthropic_api_key.present?
      return :ollama    if Ollama.new.available?
      nil
    end

    # ─── Ollama ──────────────────────────────────────────────────────────
    class Ollama
      def initialize(host: DEFAULT_OLLAMA_HOST)
        @host = host
      end

      def available?
        uri = URI("#{@host}/api/tags")
        Net::HTTP.start(uri.host, uri.port, open_timeout: 1, read_timeout: 1) do |http|
          res = http.request(Net::HTTP::Get.new(uri.path))
          return false unless res.is_a?(Net::HTTPSuccess)
          # Mindestens 1 Modell vorhanden, das nicht nur ein Embedder ist?
          # Heuristik: bge/embed im Namen → vermutlich Embedder, ignorieren.
          tags = JSON.parse(res.body)["models"] || []
          tags.any? { |m| !m["name"].to_s.match?(/embed|bge/i) }
        end
      rescue
        false
      end

      def complete(prompt:, model:, system: nil)
        uri  = URI("#{@host}/api/chat")
        msgs = []
        msgs << { role: "system",  content: system } if system.present?
        msgs << { role: "user",    content: prompt }
        body = { model: model, messages: msgs, stream: false }.to_json

        # Read-Timeout 10 min — CPU-Inferenz auf einem 8B-Modell für
        # eine ~1k-Token-Zusammenfassung dauert leicht 2–5 Minuten.
        # Erstes Laden des Modells in RAM addiert nochmal ~30–60s.
        Net::HTTP.start(uri.host, uri.port, read_timeout: 600, open_timeout: 5) do |http|
          req = Net::HTTP::Post.new(uri.path, "Content-Type" => "application/json")
          req.body = body
          res = http.request(req)
          raise UnavailableError, "Ollama HTTP #{res.code}: #{res.body.to_s.truncate(200)}" unless res.is_a?(Net::HTTPSuccess)
          JSON.parse(res.body).dig("message", "content").to_s
        end
      end
    end

    # ─── Anthropic ───────────────────────────────────────────────────────
    class Anthropic
      def initialize(api_key: ChatClient.anthropic_api_key)
        @api_key = api_key
        raise UnavailableError, "ANTHROPIC_API_KEY nicht gesetzt (auch nicht in credentials[:anthropic][:api_key])" if @api_key.blank?
      end

      def complete(prompt:, model:, system: nil, max_tokens: 2048, activity: nil)
        uri = URI("https://api.anthropic.com/v1/messages")
        body = {
          model: model,
          max_tokens: max_tokens,
          messages: [{ role: "user", content: prompt }]
        }
        body[:system] = system if system.present?

        # #614: 120s rissen bei der Transkript-Strukturierung (40-85k chars
        # Input, bis 16k Output-Tokens) regelmäßig — Net::ReadTimeout.
        # 600s wie beim lokalen Pfad; die Aufrufer tracken via LlmActivity.
        Net::HTTP.start(uri.host, uri.port, use_ssl: true, read_timeout: 600, open_timeout: 5) do |http|
          req = Net::HTTP::Post.new(uri.path,
                                     "Content-Type"      => "application/json",
                                     "x-api-key"          => @api_key,
                                     "anthropic-version"  => "2023-06-01")
          req.body = body.to_json
          res = http.request(req)
          raise UnavailableError, "Anthropic HTTP #{res.code}: #{res.body.to_s.truncate(200)}" unless res.is_a?(Net::HTTPSuccess)
          data = JSON.parse(res.body)
          # #628 W0: Usage (Tokens + Kosten) an die LlmActivity heften.
          ChatClient.record_usage(activity, model, data["usage"]) if activity
          data.dig("content", 0, "text").to_s
        end
      end
    end
  end
end
