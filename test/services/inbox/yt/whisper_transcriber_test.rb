require "test_helper"

# #1675: Scheitert ein einzelner Audio-Abschnitt (429, Zeitüberschreitung), wurde
# daraus still ein leerer Text. Bei einem zweistündigen Video fehlten so 20, 40,
# 70 Minuten MITTEN im Transkript — ohne jede Markierung, als „verarbeitet"
# verbucht. Wer es später liest oder zitiert, merkt nichts.
class Inbox::Yt::WhisperTranscriberTest < ActiveSupport::TestCase
  setup do
    @hans = create_human
  end

  # Ersetzt Download, Aufteilung, Dauer und den Whisper-Aufruf (kein
  # minitest/mock im Projekt). `antworten`: je Abschnitt ein Text oder :fehler;
  # ein Array je Abschnitt = Antworten der aufeinanderfolgenden Versuche.
  def transkribiere(antworten)
    t = Inbox::Yt::WhisperTranscriber.new(actor: @hans)
    ordner = Dir.mktmpdir("whisper-test-")
    pfade  = antworten.each_index.map { |i| File.join(ordner, "abschnitt-#{i}.mp3").tap { |pf| File.write(pf, "x") } }
    t.define_singleton_method(:split_if_needed) { |_audio, _dir| pfade }
    t.define_singleton_method(:probe_duration)  { |_pfad| 600.0 }
    t.define_singleton_method(:whisper_cost_eur) { |_sek| 0 }

    versuche = Hash.new(0)
    orig_dl = Inbox::Yt::YtDlp.method(:download_audio)
    orig_w  = Llm::WhisperClient.method(:transcribe)
    Inbox::Yt::YtDlp.define_singleton_method(:download_audio) { |_url, _dir| "/tmp/ganz.mp3" }
    Llm::WhisperClient.define_singleton_method(:transcribe) do |path:, **|
      i = pfade.index(path)
      antwort = Array(antworten[i])[versuche[i]] || Array(antworten[i]).last
      versuche[i] += 1
      raise "429 Too Many Requests" if antwort == :fehler
      { "text" => antwort, "segments" => [{ "start" => 0.0, "end" => 5.0, "text" => antwort }] }
    end
    [t.call("https://youtu.be/x"), t, versuche]
  ensure
    FileUtils.rm_rf(ordner) if ordner
    Inbox::Yt::YtDlp.define_singleton_method(:download_audio, orig_dl)
    Llm::WhisperClient.define_singleton_method(:transcribe, orig_w)
  end

  test "ein gescheiterter Abschnitt hinterlaesst eine sichtbare Luecke mit Zeitangabe" do
    text, t, = transkribiere(["Anfang.", :fehler, "Ende."])

    assert_match(/Anfang\..*Ende\./m, text)
    assert_match(/10:00.*20:00/, text, "die Lücke steht nicht mit ihrer Zeitspanne im Text")
    assert_match(/nicht transkribiert/i, text)
    assert_equal [{ abschnitt: 2, von: 600.0, bis: 1200.0 }], t.luecken
    assert t.segments.any? { |s| s["start"] == 600.0 && s["text"].match?(/nicht transkribiert/i) },
           "auch die Zeitleiste muss die Lücke zeigen"
    assert_equal 1200.0, t.segments.last["start"], "die Zeiten dahinter stimmen weiter"
  end

  test "ein voruebergehender Fehler wird einmal wiederholt, bevor eine Luecke bleibt" do
    text, t, versuche = transkribiere(["Anfang.", [:fehler, "Mitte."], "Ende."])

    assert_equal "Anfang. Mitte. Ende.", text
    assert_empty t.luecken
    assert_equal 2, versuche[1]
  end

  test "ohne Fehler bleibt alles wie bisher" do
    text, t, = transkribiere(["Eins.", "Zwei."])
    assert_equal "Eins. Zwei.", text
    assert_empty t.luecken
  end
end
