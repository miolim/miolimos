module Inbox
  module Processors
    # YouTube-URL → KI mit Metadaten + Transkript. Orchestriert die
    # Inbox::Yt::*-Helfer (yt-dlp, Whisper, Strukturierung, Summary,
    # Source-Upsert, Markdown-Build) zu einem End-to-End-Flow. Das
    # eigentliche Wissen über jeweils einen Schritt steckt in den
    # Helpern; dieser Processor verkettet sie nur.
    class YoutubeTranscribe < ProcessorBase
      def self.kind        = "youtube_transcribe"
      def self.label       = "YouTube: Metadaten + Transkript"
      def self.description = "Lädt Titel/Kanal/Beschreibung; Whisper-Transkription nach Bestätigung."

      def self.applies?(item)
        item.source_kind == "youtube_url" || youtube_url?(item.source_url)
      end

      def self.youtube_url?(url)
        # #618 v3: auch /shorts/ — Shorts landeten als web_url, dort
        # scheitert der HTML-Titel-Fetch an der Consent-Seite.
        url.to_s.match?(%r{\A(?:https?://)?(?:www\.|m\.)?(?:youtube\.com/(?:watch\?|shorts/)|youtu\.be/)})
      end

      def process!(item, actor:)
        url = item.source_url.to_s.strip
        raise "InboxItem hat keine source_url" if url.empty?

        meta = Inbox::Yt::YtDlp.fetch_metadata(url)

        transcript, whisper_used, segments, utterances = transcribe(item, meta, url, actor: actor)

        # Post-Processing via Haiku: strukturieren (Absätze + Zwischen-
        # überschriften) und Stichpunkt-Zusammenfassung. Beide optional —
        # Misserfolg führt einfach zum Weglassen, das Roh-Transkript bleibt.
        structured  = false
        timestamped = false
        diarized    = utterances.present?
        summary     = nil
        if whisper_used
          post = Inbox::Yt::TranscriptPostProcessor.new(actor: actor)
          # #660 (Hans): Liegen Segment-Zeitstempel vor, bauen wir die
          # Absätze deterministisch mit anklickbarem Zeitstempel-Link auf
          # die Video-Stelle. #660 v2: die KI ergänzt NUR die H3-Zwischen-
          # überschriften zur Gliederung (sie fasst die fertigen Absätze
          # nicht an) — Zeitstempel + Text bleiben verbatim.
          # #776 (Hans): Mit Sprechererkennung kommen die Absätze schon
          # sprecher-getaggt aus den Utterances; sonst der Segment-Pfad,
          # sonst der volle LLM-Struktur-Pass.
          paras =
            if diarized
              speaker_paragraphs(utterances, meta, url)
            elsif segments.present?
              timestamped_paragraphs(segments, meta, url)
            else
              []
            end
          if paras.present?
            headings   = post.section_headings(paras, meta)
            transcript = Inbox::Yt::TimestampedTranscript.weave(paras, headings)
            timestamped = true
            structured  = headings.present?
          elsif (improved = post.structure(transcript, meta)).present?
            transcript = improved
            structured = true
          end
          summary = post.summarize(transcript, meta)
        end

        body = Inbox::Yt::MarkdownBuilder.build(meta, transcript,
                                                whisper_used: whisper_used,
                                                structured:   structured,
                                                timestamped:  timestamped,
                                                diarized:     diarized,
                                                summary:      summary)
        title = meta["title"].presence || item.title.presence || url

        src = Inbox::Yt::SourceUpserter.call(meta, url, actor: actor)

        ki = FileProxy.create(
          actor:      actor,
          title:      title,
          item_type:  :transcript,
          content:    body,
          tags:       (Array(meta["tags"]) + ["youtube"]).uniq
        )
        if src
          ki.update!(bib_source_id: src.id)
          FileProxy.merge_frontmatter!(actor: actor, knowledge_item: ki,
                                        bib_source: src.slug)
        end
        record_result(item, knowledge_item: ki)
      end

      private

      # Liefert [transcript, used, segments, utterances]. Whisper ODER (mit
      # Bestätigung confirm_diarize + Key) AssemblyAI-Diarisierung. Ohne
      # Bestätigung: NeedsConfirmation → ProcessorBase hängt das Item in
      # awaiting_confirmation; die UI bietet je nach Verfügbarkeit beide Wege.
      def transcribe(item, meta, url, actor:)
        whisper_ok = Llm::WhisperClient.available?
        diarize_ok = Llm::DiarizationClient.available?
        return ["", false, [], []] unless whisper_ok || diarize_ok

        want_diarize = ActiveModel::Type::Boolean.new.cast(item.payload["confirm_diarize"]) && diarize_ok
        want_whisper = ActiveModel::Type::Boolean.new.cast(item.payload["confirm_whisper"]) && whisper_ok

        unless want_diarize || want_whisper
          duration = meta["duration"].to_i
          raise Inbox::ProcessorBase::NeedsConfirmation.new(
            reason:                "whisper_youtube_audio",
            duration_seconds:      duration,
            duration_human:        Inbox::Yt::MarkdownBuilder.format_duration(duration),
            whisper_available:     whisper_ok,
            estimated_eur:         (Llm::WhisperClient.estimated_eur(duration) if whisper_ok),
            diarize_available:     diarize_ok,
            diarize_estimated_eur: (Llm::DiarizationClient.estimated_eur(duration) if diarize_ok),
            processor_kind:        self.class.kind,
            confirm_param:         "confirm_whisper"
          )
        end

        lang = Inbox::Yt::MarkdownBuilder.language_hint(meta)
        if want_diarize
          transcriber = Inbox::Yt::DiarizedTranscriber.new(actor: actor)
          text = transcriber.call(url, language_hint: lang)
          [text, text.present?, [], transcriber.utterances]
        else
          transcriber = Inbox::Yt::WhisperTranscriber.new(actor: actor)
          text = transcriber.call(url, language_hint: lang)
          [text, text.present?, transcriber.segments, []]
        end
      end

      # #776: Sprecher-Absätze (Array) aus AssemblyAI-Utterances, mit dem
      # gleichen Deep-Link wie die Whisper-Zeitstempel-Absätze.
      def speaker_paragraphs(utterances, meta, url)
        vid = meta["id"].presence || youtube_id_from_url(url)
        base = vid.present? ? "https://www.youtube.com/watch?v=#{vid}" : nil
        link = base ? ->(sec) { "#{base}&t=#{sec}s" } : ->(_sec) { url }
        Inbox::Yt::TimestampedTranscript.speaker_paragraphs(utterances, link_for: link)
      end

      # #660: Zeitstempel-Absätze (Array). Deep-Link-Form `watch?v=ID&t=Ns`
      # (funktioniert auch für youtu.be/shorts). Video-ID bevorzugt aus
      # den Metadaten, sonst aus der URL.
      def timestamped_paragraphs(segments, meta, url)
        vid = meta["id"].presence || youtube_id_from_url(url)
        return [] if vid.blank?
        base = "https://www.youtube.com/watch?v=#{vid}"
        Inbox::Yt::TimestampedTranscript.paragraphs(
          segments, link_for: ->(sec) { "#{base}&t=#{sec}s" }
        )
      end

      def youtube_id_from_url(url)
        m = url.to_s.match(%r{[?&]v=([\w-]{6,})}) ||
            url.to_s.match(%r{youtu\.be/([\w-]{6,})}) ||
            url.to_s.match(%r{youtube\.com/shorts/([\w-]{6,})})
        m && m[1]
      end
    end
  end
end
