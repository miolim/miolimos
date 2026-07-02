require "net/http"
require "json"
require "uri"

module Llm
  # #776 (Hans, 2026-06-29): Transkription MIT Sprechererkennung (Diarisierung)
  # über AssemblyAI. Anders als Whisper liefert AssemblyAI in EINEM Lauf
  # Transkript + Sprecher-Zuordnung (`speaker_labels`). Optionaler Dienst:
  # ohne Key bleibt der YouTube-Flow beim normalen Whisper-Pfad.
  #
  # Key aus ENV["ASSEMBLYAI_API_KEY"] oder credentials[:assemblyai][:api_key].
  # AssemblyAI verarbeitet große Dateien serverseitig — KEIN 24-MB-Chunking
  # nötig (anders als Whisper).
  #
  # WARTUNG: Die AssemblyAI-API ändert sich. VOR Änderungen an diesem Client
  # die Live-Docs prüfen (https://www.assemblyai.com/docs/llms-full.txt) statt
  # aus dem Gedächtnis — Parameternamen/Defaults wandern (#779). Pre-recorded-
  # Fakten (Stand 2026-06-29, gegen Live-Docs verifiziert): Auth = ROHER Key
  # (kein Bearer); `/v2/upload` = raw binary; `speaker_labels:true`; Antwort
  # `utterances[{speaker,start,end(ms),text}]`; `speech_models` empfohlen.
  module DiarizationClient
    class Error < StandardError; end

    BASE_URL = "https://api.assemblyai.com/v2".freeze
    # #779: explizit gesetzt (geordnete Fallback-Liste: neuestes zuerst, dann
    # stabiler Vorgänger). Über ENV anpassbar, falls neue Modelle erscheinen.
    SPEECH_MODELS = ENV.fetch("ASSEMBLYAI_SPEECH_MODELS", "universal-3-pro,universal-2")
                       .split(",").map(&:strip).reject(&:empty?)
    # AssemblyAI „Universal" ~ 0,27 USD/Std = 0,0045 USD/Min (Speaker Labels
    # ohne Aufpreis). Überschreibbar, falls sich der Tarif ändert.
    USD_PER_MINUTE = ENV.fetch("ASSEMBLYAI_USD_PER_MINUTE", "0.0045").to_f
    USD_TO_EUR     = 0.93
    POLL_INTERVAL  = 5      # Sekunden zwischen Status-Abfragen
    POLL_TIMEOUT   = 1800   # max. 30 min auf das fertige Transkript warten

    def self.api_key
      ENV["ASSEMBLYAI_API_KEY"].presence ||
        Rails.application.credentials.dig(:assemblyai, :api_key).presence
    end

    def self.available?
      api_key.present?
    end

    def self.estimated_eur(seconds)
      ((seconds.to_f / 60.0) * USD_PER_MINUTE * USD_TO_EUR).round(2)
    end

    # Lädt die lokale Audiodatei hoch, startet eine Transkription mit
    # Sprecher-Labels, pollt bis fertig. Liefert:
    #   { "text" => "…",
    #     "utterances" => [{ "speaker" => "A", "start" => Float(sec),
    #                        "text" => "…" }, …],
    #     "audio_duration" => Integer(sec) }
    # `sleeper` injizierbar für Tests (kein echtes sleep).
    def self.transcribe(path:, language: nil, sleeper: ->(s) { sleep(s) })
      raise Error, "ASSEMBLYAI_API_KEY nicht gesetzt" unless available?
      raise Error, "Datei nicht gefunden: #{path}" unless File.exist?(path)

      upload_url = upload(path)
      id         = create_transcript(upload_url, language: language)
      poll(id, sleeper: sleeper)
    end

    # --- intern -------------------------------------------------------------

    def self.upload(path)
      res = post_raw("#{BASE_URL}/upload", File.binread(path),
                     content_type: "application/octet-stream")
      json = JSON.parse(res)
      json["upload_url"].presence || raise(Error, "Upload ohne upload_url")
    end

    def self.create_transcript(audio_url, language: nil)
      params = {
        "audio_url"      => audio_url,
        "speaker_labels" => true,
        "speech_models"  => SPEECH_MODELS  # #779: explizit (geordnete Fallback-Liste)
      }
      # Bekannte Sprache → language_code; sonst Auto-Erkennung.
      if language.present?
        params["language_code"] = language.to_s
      else
        params["language_detection"] = true
      end
      json = JSON.parse(post_json("#{BASE_URL}/transcript", params))
      json["id"].presence || raise(Error, "Transcript-Erstellung ohne id")
    end

    def self.poll(id, sleeper:)
      waited = 0
      loop do
        json = JSON.parse(get("#{BASE_URL}/transcript/#{id}"))
        case json["status"]
        when "completed" then return shape(json)
        when "error"     then raise Error, "AssemblyAI: #{json['error']}"
        end
        raise Error, "Timeout beim Warten auf Transkript #{id}" if waited >= POLL_TIMEOUT
        sleeper.call(POLL_INTERVAL)
        waited += POLL_INTERVAL
      end
    end

    # AssemblyAI liefert start/end in MILLISEKUNDEN → auf Sekunden normalisieren.
    def self.shape(json)
      utterances = Array(json["utterances"]).map do |u|
        # #776 v2 (Hans): Wort-Zeitstempel je Utterance MITNEHMEN — damit
        # lange Sprecher-Turns downstream in Absätze mit Zwischen-Zeitstempeln
        # zerlegt werden können (vorher: 1 Turn = 1 Absatz = 1 Stempel).
        words = Array(u["words"]).filter_map do |w|
          next if w["text"].to_s.strip.empty?
          { "start" => (w["start"].to_f / 1000.0),
            "end"   => (w["end"].to_f / 1000.0),
            "text"  => w["text"].to_s }
        end
        { "speaker" => u["speaker"].to_s,
          "start"   => (u["start"].to_f / 1000.0),
          "text"    => u["text"].to_s.strip,
          "words"   => words }
      end
      { "text"           => json["text"].to_s.strip,
        "utterances"     => utterances,
        "audio_duration" => json["audio_duration"].to_i }
    end

    def self.get(url)
      uri = URI(url)
      Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 5, read_timeout: 60) do |http|
        req = Net::HTTP::Get.new(uri, "Authorization" => api_key)
        ok(http.request(req))
      end
    end

    def self.post_json(url, body)
      uri = URI(url)
      Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 5, read_timeout: 60) do |http|
        req = Net::HTTP::Post.new(uri, "Authorization" => api_key, "Content-Type" => "application/json")
        req.body = JSON.generate(body)
        ok(http.request(req))
      end
    end

    def self.post_raw(url, bytes, content_type:)
      uri = URI(url)
      Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 5, read_timeout: 300) do |http|
        req = Net::HTTP::Post.new(uri, "Authorization" => api_key, "Content-Type" => content_type)
        req.body = bytes
        ok(http.request(req))
      end
    end

    def self.ok(res)
      raise Error, "AssemblyAI HTTP #{res.code}: #{res.body.to_s[0, 200]}" unless res.is_a?(Net::HTTPSuccess)
      res.body.to_s.force_encoding("UTF-8")
    end

    private_class_method :upload, :create_transcript, :poll, :shape,
                         :get, :post_json, :post_raw, :ok
  end
end
