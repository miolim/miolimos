require "test_helper"

# #1492 (Hans): „Den MP3-Weg ergänzen."
#
# Vorgeschichte: Ein Podcast liess sich nicht transkribieren, weil YouTube
# die Tonspur nicht mehr herausgab. Dieselbe Folge liegt als offene M4A in
# einem RSS-Feed — der Weg hier braucht YouTube gar nicht.
#
# Die Sonde wird mit einem ECHTEN Doppelgaenger-Programm geprueft (ein
# Skript, das feste JSON-Ausgabe liefert), nicht mit einer untergeschobenen
# Methode: Dann laeuft der Aufruf wirklich durch Open3, und ein Fehler in
# der Argumentliste faellt auf.
class Inbox::Processors::AudioTranscribeTest < ActiveSupport::TestCase
  setup do
    @hans = create_human
    grant(@hans, "KnowledgeItem", %w[read create update delete])
    grant(@hans, "Source",        %w[read create update delete])
    @proc = Inbox::Processors::AudioTranscribe.new
  end

  def item(url, payload: {})
    InboxItem.create!(creator: @hans, source_kind: "web_url", source_url: url,
                      status: "pending", payload: payload)
  end

  # ─── Erkennung ────────────────────────────────────────────────────────

  test "erkennt die ueblichen Audio-Endungen" do
    %w[folge.mp3 folge.m4a folge.wav folge.ogg folge.opus folge.flac].each do |datei|
      assert Inbox::Processors::AudioTranscribe.audio_url?("https://example.org/#{datei}"),
             "#{datei} sollte als Audio erkannt werden"
    end
  end

  # Der Feed-Anbieter des Podcasts haengt die eigentliche Datei als
  # kodierten Pfadteil an seine eigene Adresse. Genau diese Form kam aus
  # dem Feed, an ihr ist der Weg gemessen.
  test "erkennt auch die verschachtelte Adresse des Feed-Anbieters" do
    url = "https://anchor.fm/s/ffaf0910/podcast/play/123271350/" \
          "https%3A%2F%2Fd3ctxlq1ktw2nl.cloudfront.net%2Fstaging%2F2026-6-24%2F428550126.m4a"
    assert Inbox::Processors::AudioTranscribe.audio_url?(url)
  end

  test "Query und Fragment zaehlen nicht zur Endung" do
    refute Inbox::Processors::AudioTranscribe.audio_url?("https://example.org/seite?datei=lied.mp3")
    refute Inbox::Processors::AudioTranscribe.audio_url?("https://example.org/seite#lied.mp3")
    assert Inbox::Processors::AudioTranscribe.audio_url?("https://example.org/lied.mp3?token=abc")
  end

  test "haelt sich von YouTube fern" do
    yt = item("https://www.youtube.com/watch?v=abc123")
    refute Inbox::Processors::AudioTranscribe.applies?(yt),
           "YouTube gehoert zum YouTube-Weg — der kann Untertitel, dieser nicht"
    assert Inbox::Processors::AudioTranscribe.applies?(item("https://example.org/folge.mp3"))
  end

  test "kaputte Adresse ist kein Audio und wirft nicht" do
    refute Inbox::Processors::AudioTranscribe.audio_url?("h t t p://%%%")
    refute Inbox::Processors::AudioTranscribe.audio_url?(nil)
  end

  # ─── Sonde: Metadaten ohne Herunterladen ──────────────────────────────
  #
  # Die Dauer entscheidet ueber die Kostenschaetzung, und die steht VOR der
  # Bestaetigung. Muesste man dafuer erst laden, waere die Reihenfolge
  # „erst zahlen, dann fragen".

  def mit_ffprobe(json, erfolg: true)
    Dir.mktmpdir("ffprobe-") do |dir|
      pfad = File.join(dir, "ffprobe")
      File.write(pfad, "#!/usr/bin/env bash\ncat <<'JSON'\n#{json}\nJSON\nexit #{erfolg ? 0 : 1}\n")
      File.chmod(0o755, pfad)
      vorher = ENV["FFPROBE_BIN"]
      ENV["FFPROBE_BIN"] = pfad
      begin
        yield
      ensure
        ENV["FFPROBE_BIN"] = vorher
      end
    end
  end

  VOLLE_AUSGABE = {
    "format" => {
      "duration" => "4193.732993",
      "tags"     => { "title" => "Folge 15", "artist" => "Recht wissenschaftlich",
                      "date" => "2026-07-24",
                      "comment" => "Ein hinreichend langer Beschreibungstext, der wie ein Satz aussieht." }
    }
  }.to_json

  test "liest Dauer und Kennzeichen aus dem Dateikopf" do
    mit_ffprobe(VOLLE_AUSGABE) do
      m = Inbox::Audio::Sonde.call("https://example.org/folge.m4a")
      assert_equal 4194, m["duration"], "auf ganze Sekunden gerundet"
      assert_equal "Folge 15", m["title"]
      assert_equal "Recht wissenschaftlich", m["uploader"]
      assert_equal "20260724", m["upload_date"], "Form wie bei yt-dlp, damit der Markdown-Bauer sie versteht"
      assert_nil m["language"], "eine Audiodatei sagt nichts ueber ihre Sprache"
    end
  end

  test "ohne Titel im Dateikopf gilt der Titel des Eintrags" do
    mit_ffprobe({ "format" => { "duration" => "60.0", "tags" => {} } }.to_json) do
      m = Inbox::Audio::Sonde.call("https://example.org/12345.mp3", fallback_title: "Meine Folge")
      assert_equal "Meine Folge", m["title"]
    end
  end

  test "ohne alles bleibt der Dateiname" do
    mit_ffprobe({ "format" => { "duration" => "60.0" } }.to_json) do
      assert_equal "428550126", Inbox::Audio::Sonde.call("https://example.org/428550126.mp3")["title"]
    end
  end

  # Im `comment` steht oft eine Container-Notiz statt Text — bei der echten
  # Folge stand dort schlicht „Bwf". Als Beschreibung waere das Rauschen.
  test "eine Container-Notiz wird nicht zur Beschreibung" do
    mit_ffprobe({ "format" => { "duration" => "60.0", "tags" => { "comment" => "Bwf" } } }.to_json) do
      assert_nil Inbox::Audio::Sonde.call("https://example.org/f.mp3")["description"]
    end
  end

  test "ein echter Beschreibungstext kommt durch" do
    mit_ffprobe(VOLLE_AUSGABE) do
      assert_match(/hinreichend langer Beschreibungstext/,
                   Inbox::Audio::Sonde.call("https://example.org/f.m4a")["description"])
    end
  end

  # Ein Fehlschlag muss WERFEN. Ein stilles nil hiesse: Dauer 0,
  # Kostenschaetzung 0 — und der Nutzer bestaetigt einen Lauf, dessen
  # Umfang niemand kennt.
  test "ein fehlgeschlagener Aufruf wirft, statt eine leere Dauer zu liefern" do
    mit_ffprobe("{}", erfolg: false) do
      assert_raises(Inbox::Audio::Sonde::Error) do
        Inbox::Audio::Sonde.call("https://example.org/kaputt.mp3")
      end
    end
  end

  test "unlesbare Ausgabe wirft ebenfalls" do
    mit_ffprobe("kein json") do
      assert_raises(Inbox::Audio::Sonde::Error) do
        Inbox::Audio::Sonde.call("https://example.org/f.mp3")
      end
    end
  end

  # ─── Bestaetigung ─────────────────────────────────────────────────────

  def mit_diensten(whisper:, diarize:)
    w = Llm::WhisperClient.method(:available?)
    d = Llm::DiarizationClient.method(:available?)
    Llm::WhisperClient.define_singleton_method(:available?) { whisper }
    Llm::DiarizationClient.define_singleton_method(:available?) { diarize }
    yield
  ensure
    Llm::WhisperClient.define_singleton_method(:available?, w)
    Llm::DiarizationClient.define_singleton_method(:available?, d)
  end

  test "fragt vor dem Transkribieren nach, mit Dauer und Kosten" do
    i = item("https://example.org/folge.m4a")
    fehler = nil
    mit_ffprobe(VOLLE_AUSGABE) do
      mit_diensten(whisper: true, diarize: true) do
        fehler = assert_raises(Inbox::ProcessorBase::NeedsConfirmation) do
          @proc.process!(i, actor: @hans)
        end
      end
    end
    d = fehler.details.stringify_keys
    assert_equal 4194,               d["duration_seconds"]
    assert_equal "1:09:54",          d["duration_human"]
    assert_equal "audio_transcribe", d["processor_kind"]
    assert_equal false,              d["subtitles_available"],
                 "eine Audiodatei bringt keine Untertitel mit"
    # Die Bestaetigungs-Karte schaltet am `whisper_`-Praefix. Ohne ihn
    # haette der Eintrag keine Knoepfe und bliebe haengen.
    assert d["reason"].to_s.start_with?("whisper_"),
           "die Bestaetigungs-Karte erkennt den Anlass am Praefix (#{d['reason']})"
  end

  test "ohne jeden Transkriptionsweg wird nicht nach Bestaetigung gefragt" do
    with_isolated_miolimos_base do
      i = item("https://example.org/folge.m4a")
      mit_ffprobe(VOLLE_AUSGABE) do
        mit_diensten(whisper: false, diarize: false) do
          @proc.process!(i, actor: @hans)
        end
      end
      # Ausdruecklich das Transkript, nicht einfach das zuletzt angelegte:
      # Die Quelle verknuepft die Sendung als Organisations-Wissenselement,
      # und das entsteht DANACH. `.last` griff daneben — der Test hat mich
      # beim ersten Lauf prompt darauf gestossen.
      ki = KnowledgeItem.where(item_type: "transcript").order(:created_at).last
      assert_equal "Folge 15", ki.title
      assert_includes File.read(FileProxy::BASE_PATH.join(ki.file_path)),
                      "Kein Transkript verfügbar",
                      "das Wissenselement entsteht mit Metadaten und einem Vermerk"
    end
  end

  # ─── Zeitmarken ───────────────────────────────────────────────────────

  test "Zeitstempel verweisen als Medien-Marke in die Datei" do
    marke = @proc.send(:zeitmarke, "https://example.org/folge.m4a#alt")
    assert_equal "https://example.org/folge.m4a#t=90", marke.call(90),
                 "ein vorhandenes Fragment wird ersetzt, nicht angehaengt"
  end

  # ─── Quelle ───────────────────────────────────────────────────────────

  test "die Folge bekommt eine bibliographische Quelle" do
    m = { "title" => "Folge 15", "uploader" => "Recht wissenschaftlich",
          "upload_date" => "20260724", "description" => "Eine Beschreibung." }
    s = Inbox::Audio::QuellenEintrag.call(m, "https://example.org/folge.m4a", actor: @hans)
    assert s, "eine Quelle muss entstehen"
    assert_equal "podcast", s.csl_type, "CSL kennt den Typ — er trifft es besser als webpage"
    assert_equal "Folge 15", s.title
    assert_equal "Recht wissenschaftlich", s.publisher
    assert_equal Date.new(2026, 7, 24), s.issued_date
  end

  # An genau dieser Stelle ist in #1471 schon einmal eine Quelle
  # gescheitert: Die Slug-Pruefung laesst nur Kleinbuchstaben, Bindestriche,
  # Punkte und Unterstriche zu — Feed-Adressen stecken voller Prozentzeichen.
  test "auch eine Adresse voller Sonderzeichen ergibt einen speicherbaren Slug" do
    url = "https://anchor.fm/s/ffaf0910/podcast/play/123271350/" \
          "https%3A%2F%2Fd3ctxlq1ktw2nl.cloudfront.net%2Fstaging%2F2026-6-24%2F428550126.m4a"
    s = Inbox::Audio::QuellenEintrag.call({ "title" => "Folge 15" }, url, actor: @hans)
    assert s, "die Quelle muss sich speichern lassen"
    assert_match(/\Aaudio-[0-9a-f]{12}\z/, s.slug)
  end

  test "dieselbe Adresse zweimal ergibt dieselbe Quelle" do
    url = "https://example.org/folge.m4a"
    a = Inbox::Audio::QuellenEintrag.call({ "title" => "Folge 15" }, url, actor: @hans)
    b = Inbox::Audio::QuellenEintrag.call({ "title" => "Folge 15 (neu)" }, url, actor: @hans)
    assert_equal a.id, b.id
    assert_equal "Folge 15 (neu)", b.reload.title, "der Titel wird nachgezogen"
  end

  test "der Weg steht im Verarbeiten-Menue" do
    assert_includes Inbox::Registry.all, Inbox::Processors::AudioTranscribe
    assert_equal Inbox::Processors::AudioTranscribe, Inbox::Registry.find("audio_transcribe")
  end
end
