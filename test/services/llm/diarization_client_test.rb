require "test_helper"

# #776: AssemblyAI-Diarisierungs-Client. HTTP wird nicht echt aufgerufen —
# getestet werden die reinen Transformationen (shape, Kostenschätzung) und
# die Verfügbarkeits-Logik.
class Llm::DiarizationClientTest < ActiveSupport::TestCase
  D = Llm::DiarizationClient

  test "shape: Millisekunden → Sekunden, Utterances normalisiert" do
    json = {
      "text" => "Hallo. Tag.",
      "audio_duration" => 738,
      "utterances" => [
        { "speaker" => "A", "start" => 0,     "end" => 4200,  "text" => "Hallo." },
        { "speaker" => "B", "start" => 65400, "end" => 70000, "text" => "  Tag.  " }
      ]
    }
    out = D.send(:shape, json)
    assert_equal "Hallo. Tag.", out["text"]
    assert_equal 738, out["audio_duration"]
    assert_equal 2, out["utterances"].size
    assert_in_delta 0.0,  out["utterances"][0]["start"], 0.001
    assert_in_delta 65.4, out["utterances"][1]["start"], 0.001
    assert_equal "Tag.", out["utterances"][1]["text"]
    assert_equal "B",    out["utterances"][1]["speaker"]
  end

  # #776 v2: Wort-Zeitstempel je Utterance mitnehmen (ms → s), leere raus.
  test "shape: Wort-Timings werden behalten und normalisiert" do
    json = {
      "text" => "Hallo Welt.",
      "utterances" => [
        { "speaker" => "A", "start" => 0, "end" => 2000, "text" => "Hallo Welt.",
          "words" => [
            { "start" => 0,    "end" => 900,  "text" => "Hallo" },
            { "start" => 1000, "end" => 2000, "text" => "Welt." },
            { "start" => 2001, "end" => 2100, "text" => "  " }
          ] }
      ]
    }
    words = D.send(:shape, json)["utterances"][0]["words"]
    assert_equal 2, words.size, "leeres Wort fällt raus"
    assert_in_delta 1.0, words[1]["start"], 0.001
    assert_equal "Welt.", words[1]["text"]
  end

  test "estimated_eur skaliert mit der Dauer" do
    one_hour = D.estimated_eur(3600)
    assert_operator one_hour, :>, 0
    assert_in_delta D.estimated_eur(7200), one_hour * 2, 0.001
  end

  test "available? hängt am Key" do
    original = D.method(:api_key)
    D.define_singleton_method(:api_key) { nil }
    refute D.available?
    D.define_singleton_method(:api_key) { "k" }
    assert D.available?
  ensure
    D.define_singleton_method(:api_key, original)
  end

  # #779: speech_models muss explizit mit (empfohlene Fallback-Liste);
  # speaker_labels + language_code im Body.
  test "create_transcript schickt speech_models + speaker_labels + language" do
    captured = nil
    orig = D.method(:post_json)
    D.define_singleton_method(:post_json) { |_url, body| captured = body; JSON.generate("id" => "t1") }
    begin
      id = D.send(:create_transcript, "https://x/audio.mp3", language: "de")
      assert_equal "t1", id
      assert_equal true, captured["speaker_labels"]
      assert_equal %w[universal-3-pro universal-2], captured["speech_models"]
      assert_equal "de", captured["language_code"]
      refute captured.key?("language_detection"), "bei bekannter Sprache kein language_detection"
    ensure
      D.define_singleton_method(:post_json, orig)
    end
  end

  test "create_transcript ohne Sprache nutzt language_detection" do
    captured = nil
    orig = D.method(:post_json)
    D.define_singleton_method(:post_json) { |_url, body| captured = body; JSON.generate("id" => "t2") }
    begin
      D.send(:create_transcript, "https://x/audio.mp3", language: nil)
      assert_equal true, captured["language_detection"]
      refute captured.key?("language_code")
    ensure
      D.define_singleton_method(:post_json, orig)
    end
  end

  test "transcribe ohne Key wirft Error" do
    original = D.method(:api_key)
    D.define_singleton_method(:api_key) { nil }
    assert_raises(Llm::DiarizationClient::Error) { D.transcribe(path: "/tmp/x.mp3") }
  ensure
    D.define_singleton_method(:api_key, original)
  end
end
