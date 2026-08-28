module Inbox
  module Processors
    # #1492 (Hans): „Den MP3-Weg ergänzen."
    #
    # Vorgeschichte: Ein Podcast liess sich nicht transkribieren, weil
    # YouTube die Tonspur nicht mehr herausgab. Dieselbe Folge liegt aber —
    # wie bei fast jedem Podcast — als offene MP3/M4A in einem RSS-Feed;
    # genau die Datei, die auch Spotify abspielt. Dieser Weg braucht weder
    # YouTube noch yt-dlps Zugangstricks und faellt deshalb nicht aus,
    # wenn dort wieder etwas umgestellt wird.
    #
    # Neu ist hier nur die Beschaffung der Metadaten (Inbox::Audio::Sonde
    # statt yt-dlp) und der Zeitmarken-Link. Transkription, Sprecher-
    # erkennung, Strukturierung, Zusammenfassung, Quelle und Markdown-Bau
    # sind dieselben Bausteine wie beim YouTube-Weg.
    class AudioTranscribe < ProcessorBase
      def self.kind        = "audio_transcribe"
      def self.label       = "Audio-Adresse: Transkript"
      def self.description = "MP3/M4A hinter einer Adresse (z. B. Podcast-Folge) transkribieren."

      ENDUNGEN = %w[.mp3 .m4a .m4b .aac .wav .ogg .oga .opus .flac .wma].freeze

      def self.applies?(item)
        return false if YoutubeTranscribe.youtube_url?(item.source_url)
        audio_url?(item.source_url)
      end

      # Erkannt wird an der Endung im PFAD — Query und Fragment bleiben
      # aussen vor. Der Feed-Anbieter des Podcasts haengt die eigentliche
      # Datei als kodierten Pfadteil an seine eigene Adresse
      # (`…/play/123/https%3A%2F%2F…%2Ffolge.m4a`); auch das endet auf `.m4a`
      # und wird damit erkannt.
      #
      # Absichtlich KEIN HEAD-Aufruf zum Pruefen des Inhaltstyps: `applies?`
      # baut die Vorschlagsliste der Inbox und laeuft fuer jeden Eintrag —
      # ein Netzaufruf je Zeile waere dort falsch. Wird eine Adresse nicht
      # erkannt, laesst sich der Weg im Verarbeiten-Menue von Hand waehlen.
      def self.audio_url?(url)
        pfad = URI.parse(url.to_s.strip).path.to_s.downcase
        ENDUNGEN.any? { |e| pfad.end_with?(e) }
      rescue URI::InvalidURIError
        false
      end

      def process!(item, actor:)
        url = item.source_url.to_s.strip
        raise "InboxItem hat keine source_url" if url.empty?

        meta = Inbox::Audio::Sonde.call(url, fallback_title: item.title.presence || item.payload["title"])

        transcript, transcript_da, segments, utterances, via = transcribe(item, meta, url, actor: actor)

        structured  = false
        timestamped = false
        diarized    = utterances.present?
        summary     = nil
        if transcript_da
          post  = Inbox::Yt::TranscriptPostProcessor.new(actor: actor)
          paras =
            if diarized
              Inbox::Yt::TimestampedTranscript.speaker_paragraphs(utterances, link_for: zeitmarke(url))
            elsif segments.present?
              Inbox::Yt::TimestampedTranscript.paragraphs(segments, link_for: zeitmarke(url))
            else
              []
            end
          if paras.present?
            headings    = post.section_headings(paras, meta)
            transcript  = Inbox::Yt::TimestampedTranscript.weave(paras, headings)
            timestamped = true
            structured  = headings.present?
          elsif (improved = post.structure(transcript, meta)).present?
            transcript = improved
            structured = true
          end
          summary = post.summarize(transcript, meta)
        end

        body = Inbox::Yt::MarkdownBuilder.build(meta, transcript,
                                                whisper_used: transcript_da,
                                                via:          via,
                                                structured:   structured,
                                                timestamped:  timestamped,
                                                diarized:     diarized,
                                                summary:      summary)

        ki = FileProxy.create(
          actor:     actor,
          title:     meta["title"].presence || item.title.presence || url,
          item_type: :transcript,
          content:   body,
          tags:      ["audio"]
        )
        # Die Quelle darf scheitern, ohne den Clip mitzureissen — aber
        # NICHT stillschweigend. Der YouTube-Upserter verschluckt jeden
        # Fehler zu einem `nil`; dann steht ein Wissenselement ohne Herkunft
        # da und der Grund nur in einer Logzeile (das war #1471). Hier wird
        # er am Eintrag vermerkt, wo er beim Nachsehen auffaellt.
        quellen_fehler = nil
        begin
          src = Inbox::Audio::QuellenEintrag.call(meta, url, actor: actor)
          if src
            ki.update!(bib_source_id: src.id)
            FileProxy.merge_frontmatter!(actor: actor, knowledge_item: ki, bib_source: src.slug)
          end
        rescue => e
          quellen_fehler = "#{e.class}: #{e.message}"
          Rails.logger.warn("Audio-Quelle fehlgeschlagen: #{quellen_fehler}")
        end

        record_result(item, knowledge_item: ki)
        item.update_column(:result, item.result.merge("source_error" => quellen_fehler)) if quellen_fehler
      end

      private

      # Zeitmarken-Link auf eine Mediendatei: `…/folge.m4a#t=123`. Das ist
      # die Media-Fragments-Schreibweise, die Browser beim direkten Abspielen
      # auswerten. Kein Deep-Link ins Video wie bei YouTube, aber besser als
      # ein Zeitstempel, der nirgendwohin fuehrt.
      def zeitmarke(url)
        basis = url.to_s.split("#").first
        ->(sec) { "#{basis}#t=#{sec}" }
      end

      # Wie beim YouTube-Weg, nur ohne Untertitel-Zweig: Eine Audiodatei
      # bringt keine mit. Bleiben Whisper und die Sprechererkennung.
      def transcribe(item, meta, url, actor:)
        whisper_ok = Llm::WhisperClient.available?
        diarize_ok = Llm::DiarizationClient.available?
        return ["", false, [], [], nil] unless whisper_ok || diarize_ok

        want_diarize = ActiveModel::Type::Boolean.new.cast(item.payload["confirm_diarize"]) && diarize_ok
        want_whisper = ActiveModel::Type::Boolean.new.cast(item.payload["confirm_whisper"]) && whisper_ok

        unless want_diarize || want_whisper
          duration = meta["duration"].to_i
          raise Inbox::ProcessorBase::NeedsConfirmation.new(
            reason:                "whisper_audio_url",
            duration_seconds:      duration,
            duration_human:        Inbox::Yt::MarkdownBuilder.format_duration(duration),
            whisper_available:     whisper_ok,
            estimated_eur:         (Llm::WhisperClient.estimated_eur(duration) if whisper_ok),
            diarize_available:     diarize_ok,
            diarize_estimated_eur: (Llm::DiarizationClient.estimated_eur(duration) if diarize_ok),
            subtitles_available:   false,
            processor_kind:        self.class.kind,
            confirm_param:         "confirm_whisper"
          )
        end

        lang = Inbox::Yt::MarkdownBuilder.language_hint(meta)
        if want_diarize
          t = Inbox::Yt::DiarizedTranscriber.new(actor: actor)
          text = t.call(url, language_hint: lang)
          [text, text.present?, [], t.utterances, :diarize]
        else
          t = Inbox::Yt::WhisperTranscriber.new(actor: actor)
          text = t.call(url, language_hint: lang)
          [text, text.present?, t.segments, [], :whisper]
        end
      end
    end
  end
end
