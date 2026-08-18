require "tmpdir"
require "json"

module Inbox
  module Yt
    # #1410 (Hans): Transkript aus den (automatischen) YouTube-Untertiteln,
    # ohne Audio-Download und ohne Transkriptionskosten.
    #
    # Der Weg für Videos, deren Tonspur YouTube nicht herausgibt — bei Hans'
    # Seth-Godin-Video antwortet der Audio-Stream mit 403, die Untertitel
    # liegen aber in 157 Sprachen bereit.
    #
    # Was man dafür in Kauf nimmt, und warum die Nachbearbeitung hier nicht
    # optional ist: Automatische Untertitel kommen OHNE Satzzeichen, ohne
    # Groß-/Kleinschreibung und ohne Absätze — ein Fließband aus Wörtern.
    # Lesbar wird das erst durch den Struktur-Pass des
    # TranscriptPostProcessor, der Satzzeichen und Absätze einzieht.
    # Sprecher werden nicht unterschieden; wer das braucht, braucht Audio.
    class SubtitleTranscriber
      def initialize(actor:)
        @actor = actor
      end

      # Sprachwahl: die Sprache des Videos, sonst Englisch, sonst die erste
      # angebotene. Lieber die Originalsprache als eine Übersetzung — die
      # automatische Übersetzung setzt auf die automatische Erkennung auf und
      # verdoppelt deren Fehler.
      def self.language_for(meta)
        angeboten = ((meta["subtitles"] || {}).keys + (meta["automatic_captions"] || {}).keys).uniq
        return nil if angeboten.empty?

        video = meta["language"].to_s.presence
        angeboten.find { |l| l == video } ||
          angeboten.find { |l| l.start_with?("#{video}-") } ||
          angeboten.find { |l| l == "en" } ||
          angeboten.first
      end

      def self.available?(meta) = language_for(meta).present?

      def call(url, meta)
        lang = self.class.language_for(meta) or
          raise YtDlp::Error, "Für dieses Video bietet YouTube keine Untertitel an"

        text = ""
        LlmActivity.track(
          kind: :inbox_youtube_subtitles, actor: @actor,
          source_kind: "url", source_id: url,
          input_summary: "Untertitel (#{lang}) statt Audio für #{url}",
          model: "yt-dlp"
        ) do
          Dir.mktmpdir("yt-subs-") do |dir|
            pfad = YtDlp.download_subtitles(url, dir, lang: lang)
            text = self.class.parse_json3(File.read(pfad))
          end
          raise YtDlp::Error, "Untertitel-Datei enthielt keinen Text" if text.blank?

          # Kein cost_eur: Untertitel kosten nichts. Genau das ist ihr Reiz.
          { output: text }
        end
        text
      end

      # json3: { "events": [ { "segs": [ { "utf8": "…" } ] }, … ] }.
      # Leerzeilen und die reinen Positions-Events fallen weg.
      def self.parse_json3(raw)
        daten = JSON.parse(raw)
        Array(daten["events"]).filter_map { |ev|
          Array(ev["segs"]).map { |s| s["utf8"] }.join.strip.presence
        }.join(" ").squeeze(" ").strip
      rescue JSON::ParserError => e
        raise YtDlp::Error, "Untertitel-Datei nicht lesbar: #{e.message}"
      end
    end
  end
end
