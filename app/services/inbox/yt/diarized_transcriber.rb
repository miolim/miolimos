require "tmpdir"

module Inbox
  module Yt
    # #776 (Hans, 2026-06-29): YouTube-Audio MIT Sprechererkennung
    # transkribieren — Audio von yt-dlp ziehen, an AssemblyAI schicken
    # (das macht Transkript + Diarisierung serverseitig in einem Lauf,
    # daher kein Chunking wie bei Whisper). Nach `call`:
    #   - `utterances` = [{ "speaker" => "A", "start" => Float(sec),
    #                       "text" => "…" }, …] (Basis für Sprecher-Absätze)
    # LlmActivity wird wie beim Whisper-Pfad getrackt.
    #
    # #1410: Ein Fehler wird NICHT mehr geschluckt. Vorher fing `call` alles
    # ab und gab "" zurück — das Wissenselement entstand dann ohne Transkript,
    # das Inbox-Item galt als verarbeitet, und nichts sagte, warum. Jetzt
    # schlägt der Fehler bis zur ProcessorBase durch: Das Item steht auf
    # `failed`, trägt den Grund und lässt sich erneut anstoßen.
    class DiarizedTranscriber
      attr_reader :utterances

      def initialize(actor:)
        @actor      = actor
        @utterances = []
      end

      def call(url, language_hint: nil)
        result = ""
        @utterances = []
        LlmActivity.track(
          kind: :inbox_youtube_diarize, actor: @actor,
          source_kind: "url", source_id: url,
          input_summary: "Diarisierte Transkription (AssemblyAI) für #{url}",
          model: "assemblyai"
        ) do
          duration_sec = nil
          Dir.mktmpdir("yt-audio-") do |dir|
            # #1410: KEIN `break if audio.nil?` mehr — der Download wirft jetzt.
            # Vorher wurde ein fehlgeschlagener Download zu einem leeren
            # Transkript, das als Erfolg verbucht wurde.
            audio = YtDlp.download_audio(url, dir)

            resp = Llm::DiarizationClient.transcribe(path: audio, language: language_hint)
            @utterances  = Array(resp["utterances"])
            result       = resp["text"].to_s.strip
            duration_sec = resp["audio_duration"].to_i
          end
          { output: result, cost_eur: diarize_cost_eur(duration_sec) }
        end
        result
      end

      private

      def diarize_cost_eur(duration_sec)
        return nil unless duration_sec&.positive?
        Llm::DiarizationClient.estimated_eur(duration_sec)
      end
    end
  end
end
