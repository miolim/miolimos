require "test_helper"

# End-to-end-Tests für den (jetzt orchestrierenden) YT-Processor.
# Reine Helfer (Markdown-Build, Format, Language-Hint, …) leben jetzt
# in Inbox::Yt::* und haben dort eigene Tests.
class Inbox::Processors::YoutubeTranscribeTest < ActiveSupport::TestCase
  setup do
    @hans = create_human
    grant(@hans, "KnowledgeItem", %w[read create update delete])
    @url = "https://www.youtube.com/watch?v=abc123"
  end

  def with_whisper_available(value)
    original = Llm::WhisperClient.method(:available?)
    Llm::WhisperClient.define_singleton_method(:available?) { value }
    yield
  ensure
    Llm::WhisperClient.define_singleton_method(:available?, original)
  end

  test "applies? matches youtube URLs and source_kind" do
    item = InboxItem.new(source_kind: "youtube_url", source_url: @url)
    assert Inbox::Processors::YoutubeTranscribe.applies?(item)

    item2 = InboxItem.new(source_kind: "web_url", source_url: @url)
    assert Inbox::Processors::YoutubeTranscribe.applies?(item2)

    item3 = InboxItem.new(source_kind: "web_url", source_url: "https://example.com/x")
    refute Inbox::Processors::YoutubeTranscribe.applies?(item3)
  end

  test "youtube_url? recognizes common variants" do
    p = Inbox::Processors::YoutubeTranscribe
    assert p.youtube_url?("https://www.youtube.com/watch?v=abc")
    assert p.youtube_url?("https://m.youtube.com/watch?v=abc")
    assert p.youtube_url?("https://youtu.be/abc")
    assert p.youtube_url?("https://www.youtube.com/shorts/Tkho0C9jqB8")   # #618 v3
    assert p.youtube_url?("https://m.youtube.com/shorts/0zqmlklcY-U")
    refute p.youtube_url?("https://vimeo.com/123")
    refute p.youtube_url?(nil)
  end

  test "process! orchestriert yt-dlp + whisper-stub + structure + summary + source-upsert" do
    with_isolated_miolimos_base do
      item = InboxItem.create!(
        source_kind: "youtube_url", source_url: @url,
        payload: { "confirm_whisper" => true },
        status: "pending", creator: @hans
      )

      meta = {
        "id" => "abc123", "title" => "Mein Video",
        "uploader" => "Kanal X", "duration" => 600,
        "upload_date" => "20240601", "description" => "Hi",
        "language" => "de", "webpage_url" => @url
      }

      # YtDlp.fetch_metadata stub
      original_meta = Inbox::Yt::YtDlp.method(:fetch_metadata)
      Inbox::Yt::YtDlp.define_singleton_method(:fetch_metadata) { |_url| meta }

      # WhisperTranscriber#call stub via instance-method Patch
      original_call = Inbox::Yt::WhisperTranscriber.instance_method(:call)
      Inbox::Yt::WhisperTranscriber.define_method(:call) { |_url, **| "Roh-Transkript Text" }

      chat_responder = ->(prompt:, **) { prompt =~ /strukturiere/i ? ("y" * 800) : "- Punkt A\n- Punkt B" }

      begin
        stub_chat_client(chat_responder) do
          with_whisper_available(true) do
            Current.set(actor: @hans) do
              Inbox::Processors::YoutubeTranscribe.new.process!(item, actor: @hans)
            end
          end

          created_uuid = item.reload.result["created"].first["uuid"]
          ki = KnowledgeItem.find(created_uuid)
          body = FileProxy.read_body(actor: @hans, knowledge_item: ki)
          assert_equal "Mein Video", ki.title
          assert_match "**Kanal:** Kanal X", body
          assert_match "## Zusammenfassung",  body
          assert_match "- Punkt A",           body
          assert_match "## Transkript (Whisper, strukturiert)", body

          assert_equal "yt-abc123", Source.find(ki.bib_source_id).slug
          assert_equal 1, LlmActivity.where(kind: "inbox_youtube_structure").count
          assert_equal 1, LlmActivity.where(kind: "inbox_youtube_summary").count
        end
      ensure
        Inbox::Yt::YtDlp.define_singleton_method(:fetch_metadata, original_meta)
        Inbox::Yt::WhisperTranscriber.define_method(:call, original_call)
      end
    end
  end

  test "process! raises NeedsConfirmation when Whisper is available but not yet confirmed" do
    item = InboxItem.create!(
      source_kind: "youtube_url", source_url: @url,
      payload: {}, status: "pending", creator: @hans
    )
    meta = { "id" => "abc", "duration" => 1800, "title" => "T" }
    original_meta = Inbox::Yt::YtDlp.method(:fetch_metadata)
    Inbox::Yt::YtDlp.define_singleton_method(:fetch_metadata) { |_url| meta }

    begin
      with_whisper_available(true) do
        err = assert_raises(Inbox::ProcessorBase::NeedsConfirmation) do
          Inbox::Processors::YoutubeTranscribe.new.process!(item, actor: @hans)
        end
        assert_equal "whisper_youtube_audio", err.details[:reason]
        assert_equal 1800,                    err.details[:duration_seconds]
        assert_equal "youtube_transcribe",    err.details[:processor_kind]
      end
    ensure
      Inbox::Yt::YtDlp.define_singleton_method(:fetch_metadata, original_meta)
    end
  end

  test "process! works without Whisper — creates a KI with no-transcript marker" do
    with_isolated_miolimos_base do
      item = InboxItem.create!(
        source_kind: "youtube_url", source_url: @url,
        payload: {}, status: "pending", creator: @hans
      )
      meta = { "id" => "abc", "title" => "Ohne Transkript", "duration" => 60 }
      original_meta = Inbox::Yt::YtDlp.method(:fetch_metadata)
      Inbox::Yt::YtDlp.define_singleton_method(:fetch_metadata) { |_url| meta }

      begin
        # #785: explizit BEIDE Dienste aus — sonst sieht der Test den echten
        # AssemblyAI-Key in den (geteilten) Credentials und der Processor
        # verlangt eine Bestätigung statt leer durchzulaufen.
        with_whisper_available(false) do
          with_diarize_available(false) do
            Current.set(actor: @hans) do
              Inbox::Processors::YoutubeTranscribe.new.process!(item, actor: @hans)
            end
          end
        end
        ki = KnowledgeItem.find(item.reload.result["created"].first["uuid"])
        body = FileProxy.read_body(actor: @hans, knowledge_item: ki)
        assert_match "Kein Transkript verfügbar", body
        assert_equal 0, LlmActivity.count, "Ohne Whisper keine LLM-Activities"
      ensure
        Inbox::Yt::YtDlp.define_singleton_method(:fetch_metadata, original_meta)
      end
    end
  end

  test "process! raises when source_url is blank" do
    item = InboxItem.create!(
      source_kind: "youtube_url", source_url: "",
      payload: {}, status: "pending", creator: @hans
    )
    err = assert_raises(RuntimeError) do
      Inbox::Processors::YoutubeTranscribe.new.process!(item, actor: @hans)
    end
    assert_match "keine source_url", err.message
  end

  # ── #776: Sprechererkennung (Diarisierung) ──────────────────────────────
  def with_diarize_available(value)
    original = Llm::DiarizationClient.method(:available?)
    Llm::DiarizationClient.define_singleton_method(:available?) { value }
    yield
  ensure
    Llm::DiarizationClient.define_singleton_method(:available?, original)
  end

  test "Gate bietet die Diarisierung an, wenn AssemblyAI verfügbar ist" do
    item = InboxItem.create!(source_kind: "youtube_url", source_url: @url,
                             payload: {}, status: "pending", creator: @hans)
    meta = { "id" => "abc", "duration" => 1800, "title" => "T" }
    original_meta = Inbox::Yt::YtDlp.method(:fetch_metadata)
    Inbox::Yt::YtDlp.define_singleton_method(:fetch_metadata) { |_url| meta }
    begin
      with_whisper_available(true) do
        with_diarize_available(true) do
          err = assert_raises(Inbox::ProcessorBase::NeedsConfirmation) do
            Inbox::Processors::YoutubeTranscribe.new.process!(item, actor: @hans)
          end
          assert_equal true, err.details[:whisper_available]
          assert_equal true, err.details[:diarize_available]
          assert err.details[:diarize_estimated_eur], "Diarisierungs-Kostenschätzung fehlt"
        end
      end
    ensure
      Inbox::Yt::YtDlp.define_singleton_method(:fetch_metadata, original_meta)
    end
  end

  test "process! mit confirm_diarize erzeugt sprecher-getaggte Absätze" do
    with_isolated_miolimos_base do
      item = InboxItem.create!(
        source_kind: "youtube_url", source_url: @url,
        payload: { "confirm_diarize" => true },
        status: "pending", creator: @hans
      )
      meta = { "id" => "abc123", "title" => "Interview", "duration" => 600, "language" => "de" }
      original_meta = Inbox::Yt::YtDlp.method(:fetch_metadata)
      Inbox::Yt::YtDlp.define_singleton_method(:fetch_metadata) { |_url| meta }

      # DiarizedTranscriber#call stubben: Utterances setzen + Text liefern.
      original_call = Inbox::Yt::DiarizedTranscriber.instance_method(:call)
      Inbox::Yt::DiarizedTranscriber.define_method(:call) do |_url, **|
        @utterances = [
          { "speaker" => "A", "start" => 0.0,  "text" => "Willkommen zum Gespräch." },
          { "speaker" => "B", "start" => 12.0, "text" => "Danke für die Einladung." }
        ]
        "Willkommen zum Gespräch. Danke für die Einladung."
      end
      chat_responder = ->(prompt:, **) { "- Punkt A" }
      begin
        stub_chat_client(chat_responder) do
          with_whisper_available(true) do
            with_diarize_available(true) do
              Current.set(actor: @hans) do
                Inbox::Processors::YoutubeTranscribe.new.process!(item, actor: @hans)
              end
            end
          end
          ki = KnowledgeItem.find(item.reload.result["created"].first["uuid"])
          body = FileProxy.read_body(actor: @hans, knowledge_item: ki)
          assert_match "## Transkript (mit Sprechererkennung, Zeitstempel)", body
          assert_match "**Sprecher A:** Willkommen zum Gespräch.", body
          assert_match "**Sprecher B:** Danke für die Einladung.", body
          assert_match "&t=12s", body, "Zeitstempel-Deeplink fehlt"
        end
      ensure
        Inbox::Yt::YtDlp.define_singleton_method(:fetch_metadata, original_meta)
        Inbox::Yt::DiarizedTranscriber.define_method(:call, original_call)
      end
    end
  end

  # ── #1410: ein fehlgeschlagener Download ist kein leeres Transkript ──────
  #
  # Der Befund aus Hans' Fall: Der Audio-Download scheiterte, `download_audio`
  # gab `nil` zurück, beide Transkriptions-Wege machten daraus stillschweigend
  # ein leeres Transkript — die LLM-Aktivität stand auf „erfolgreich", das
  # Wissenselement entstand ohne Text, das Inbox-Item galt als verarbeitet.
  # Sichtbar war: kein Transkript, kein Grund.

  def with_download_failing(meldung)
    original = Inbox::Yt::YtDlp.method(:download_audio)
    Inbox::Yt::YtDlp.define_singleton_method(:download_audio) do |_url, _dir|
      raise Inbox::Yt::YtDlp::Error, meldung
    end
    yield
  ensure
    Inbox::Yt::YtDlp.define_singleton_method(:download_audio, original)
  end

  test "yt-dlp meldet den Grund, statt still nil zu liefern" do
    fehler = assert_raises(Inbox::Yt::YtDlp::Error) do
      original = Open3.method(:capture3)
      Open3.define_singleton_method(:capture3) do |*_args|
        ["", "WARNUNG: irgendwas\nERROR: Sign in to confirm you are not a bot\n",
         Struct.new(:success?).new(false)]
      end
      begin
        Inbox::Yt::YtDlp.download_audio("https://www.youtube.com/watch?v=x", "/tmp")
      ensure
        Open3.define_singleton_method(:capture3, original)
      end
    end
    assert_match(/Sign in to confirm/, fehler.message, "der Grund von yt-dlp muss mitkommen")
  end

  test "scheiternder Download laesst die diarisierte Transkription fehlschlagen" do
    with_download_failing("yt-dlp Audio-Download fehlgeschlagen: ERROR: Video unavailable") do
      t = Inbox::Yt::DiarizedTranscriber.new(actor: @hans)
      assert_raises(Inbox::Yt::YtDlp::Error) { t.call("https://www.youtube.com/watch?v=x") }
    end
    a = LlmActivity.where(kind: "inbox_youtube_diarize").order(:created_at).last
    assert_equal "failed", a.status, "eine gescheiterte Transkription darf nicht als Erfolg zaehlen"
    assert_match(/Video unavailable/, a.error_message.to_s)
  end

  test "scheiternder Download laesst die Whisper-Transkription fehlschlagen" do
    with_download_failing("yt-dlp Audio-Download fehlgeschlagen: ERROR: gesperrt") do
      t = Inbox::Yt::WhisperTranscriber.new(actor: @hans)
      assert_raises(Inbox::Yt::YtDlp::Error) { t.call("https://www.youtube.com/watch?v=x") }
    end
    a = LlmActivity.where(kind: "inbox_youtube_whisper").order(:created_at).last
    assert_equal "failed", a.status
    assert_match(/gesperrt/, a.error_message.to_s)
  end

  # Und das Ergebnis, das Hans sehen soll: kein stiller Erfolg mehr, sondern
  # ein Item mit Grund, das man erneut anstossen kann.
  test "das Inbox-Item traegt danach den Grund statt still verarbeitet zu sein" do
    with_isolated_miolimos_base do
      meta = { "id" => "abc123", "title" => "Video", "duration" => 6786,
               "uploader" => "Kanal", "description" => "x", "upload_date" => "20260810" }
      original_meta = Inbox::Yt::YtDlp.method(:fetch_metadata)
      Inbox::Yt::YtDlp.define_singleton_method(:fetch_metadata) { |_url| meta }
      begin
        with_whisper_available(true) do
          with_download_failing("yt-dlp Audio-Download fehlgeschlagen: ERROR: Sign in to confirm you are not a bot") do
            item = InboxItem.create!(creator: @hans, source_kind: "youtube_url",
                                     source_url: @url, title: "Video",
                                     status: "pending", payload: { "confirm_whisper" => true })
            Inbox::Processors::YoutubeTranscribe.run(item, actor: @hans) rescue nil
            item.reload
            assert_equal "failed", item.status, "nicht mehr still auf processed"
            assert_match(/not a bot/, item.error_message.to_s, "der Grund muss am Item stehen")
          end
        end
      ensure
        Inbox::Yt::YtDlp.define_singleton_method(:fetch_metadata, original_meta)
      end
    end
  end

  # ── #1410: Transkript aus Untertiteln ───────────────────────────────────

  JSON3 = {
    "events" => [
      { "segs" => [{ "utf8" => "so i quit" }] },
      { "segs" => [{ "utf8" => "\n" }] },
      { "segs" => [{ "utf8" => "and that" }, { "utf8" => " changed everything" }] }
    ]
  }.freeze

  test "json3 wird zu Fliesstext, Leer-Events fallen weg" do
    text = Inbox::Yt::SubtitleTranscriber.parse_json3(JSON3.to_json)
    assert_equal "so i quit and that changed everything", text
  end

  # Originalsprache schlaegt Englisch schlaegt Irgendwas — eine automatische
  # UEbersetzung setzt auf der automatischen Erkennung auf und verdoppelt
  # deren Fehler.
  test "Sprachwahl bevorzugt die Sprache des Videos" do
    f = Inbox::Yt::SubtitleTranscriber
    assert_equal "de", f.language_for({ "language" => "de", "automatic_captions" => { "en" => [], "de" => [] } })
    assert_equal "en", f.language_for({ "language" => "xx", "automatic_captions" => { "en" => [], "fr" => [] } })
    assert_equal "fr", f.language_for({ "automatic_captions" => { "fr" => [] } })
    assert_nil   f.language_for({ "automatic_captions" => {} })
    assert_not   f.available?({ "automatic_captions" => {} })
  end

  test "Untertitel ohne Text sind kein Transkript" do
    original = Inbox::Yt::YtDlp.method(:download_subtitles)
    Inbox::Yt::YtDlp.define_singleton_method(:download_subtitles) do |_url, dir, lang: nil|
      pfad = File.join(dir, "sub.en.json3")
      File.write(pfad, { "events" => [] }.to_json)
      pfad
    end
    begin
      t = Inbox::Yt::SubtitleTranscriber.new(actor: @hans)
      assert_raises(Inbox::Yt::YtDlp::Error) { t.call(@url, { "language" => "en", "automatic_captions" => { "en" => [] } }) }
      a = LlmActivity.where(kind: "inbox_youtube_subtitles").order(:created_at).last
      assert_equal "failed", a.status
    ensure
      Inbox::Yt::YtDlp.define_singleton_method(:download_subtitles, original)
    end
  end

  # Der Weg, den Hans wollte: kein Audio, keine Kosten, und der
  # Nachbearbeitungs-Pass zieht Satzzeichen und Absaetze ein.
  test "Untertitel-Weg erzeugt ein nachbearbeitetes Transkript ohne Audio-Download" do
    with_isolated_miolimos_base do
      meta = { "id" => "abc123", "title" => "Video", "duration" => 6786,
               "uploader" => "Kanal", "description" => "x", "upload_date" => "20260810",
               "language" => "en", "automatic_captions" => { "en" => [{ "ext" => "json3" }] } }
      orig_meta = Inbox::Yt::YtDlp.method(:fetch_metadata)
      orig_subs = Inbox::Yt::YtDlp.method(:download_subtitles)
      orig_dl   = Inbox::Yt::YtDlp.method(:download_audio)
      Inbox::Yt::YtDlp.define_singleton_method(:fetch_metadata) { |_url| meta }
      Inbox::Yt::YtDlp.define_singleton_method(:download_subtitles) do |_url, dir, lang: nil|
        pfad = File.join(dir, "sub.en.json3")
        File.write(pfad, JSON3.to_json)
        pfad
      end
      # Wird der Audio-Download angefasst, ist der Weg falsch gebaut.
      Inbox::Yt::YtDlp.define_singleton_method(:download_audio) do |_url, _dir|
        raise "Audio-Download darf beim Untertitel-Weg NICHT aufgerufen werden"
      end
      begin
        strukturiert = "So I quit. And that changed everything."
        stub_chat_client(->(**_kw) { strukturiert }) do
          item = InboxItem.create!(creator: @hans, source_kind: "youtube_url",
                                   source_url: @url, title: "Video", status: "pending",
                                   payload: { "confirm_subtitles" => true })
          Inbox::Processors::YoutubeTranscribe.run(item, actor: @hans)
          item.reload
          assert_equal "processed", item.status, item.error_message.to_s
          ki = KnowledgeItem.find(item.result.dig("created", 0, "uuid"))
          assert_match(/aus automatischen Untertiteln/, ki.body, "Herkunft gehoert in die Ueberschrift")
          assert_match(/So I quit\./, ki.body, "der Struktur-Pass zieht Satzzeichen ein")
        end
      ensure
        Inbox::Yt::YtDlp.define_singleton_method(:fetch_metadata, orig_meta)
        Inbox::Yt::YtDlp.define_singleton_method(:download_subtitles, orig_subs)
        Inbox::Yt::YtDlp.define_singleton_method(:download_audio, orig_dl)
      end
    end
  end
end
