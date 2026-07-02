require "test_helper"

# #778: TED-Transkript-Parser (reine Funktionen).
class Inbox::Ted::TranscriptTest < ActiveSupport::TestCase
  T = Inbox::Ted::Transcript

  NEXT_JSON = {
    "props" => { "pageProps" => {
      "videoData" => {
        "id" => "123", "title" => "Mein Talk", "presenterDisplayName" => "Jane Doe",
        "duration" => 90, "recordedOn" => "2020-01-02",
        "publishedAt" => "2020-02-03T00:00:00Z", "description" => "Eine Beschreibung.",
        "canonicalUrl" => "https://www.ted.com/talks/jane", "internalLanguageCode" => "en",
        "topics" => { "nodes" => [{ "name" => "science" }] }
      },
      "transcriptData" => { "translation" => { "paragraphs" => [
        { "cues" => [{ "text" => "Hello there.", "time" => 0 }, { "text" => "Welcome.", "time" => 2000 }] },
        { "cues" => [{ "text" => "Second para.", "time" => 65000 }] }
      ] } }
    } }
  }.freeze

  def html(next_json = NEXT_JSON)
    %(<html><body><script id="__NEXT_DATA__" type="application/json">#{JSON.generate(next_json)}</script></body></html>)
  end

  def link
    ->(sec) { "https://www.ted.com/talks/jane#t=#{sec}" }
  end

  test "extract: liefert videoData + paragraphs" do
    data = T.extract(html)
    assert_equal "Mein Talk", data["video"]["title"]
    assert_equal 2, data["paragraphs"].size
  end

  test "extract: kaputtes/fehlendes __NEXT_DATA__ → leere Struktur" do
    assert_equal({ "video" => {}, "paragraphs" => [] }, T.extract("<html>nix</html>"))
    assert_equal({ "video" => {}, "paragraphs" => [] }, T.extract(%(<script id="__NEXT_DATA__">{kaputt</script>)))
  end

  test "paragraphs_markdown: Zeitstempel (ms→s), Cues verbunden, Link" do
    md = T.paragraphs_markdown(T.extract(html)["paragraphs"], link_for: link)
    assert_equal 2, md.size
    assert_equal "[0:00](https://www.ted.com/talks/jane#t=0) Hello there. Welcome.", md[0]
    assert_equal "[1:05](https://www.ted.com/talks/jane#t=65) Second para.", md[1]
  end

  test "build_markdown: Metadaten + Transkript-Überschrift" do
    md = T.build_markdown(T.extract(html)["video"], T.paragraphs_markdown(T.extract(html)["paragraphs"], link_for: link))
    assert_match "**Sprecher:** Jane Doe", md
    assert_match "**Dauer:** 1:30", md
    assert_match "**Aufgenommen:** 2020-01-02", md
    assert_match "## Transkript (TED, offiziell)", md
    assert_match "Hello there. Welcome.", md
  end

  test "build_markdown: ohne Transkript ein Hinweis statt Überschrift" do
    md = T.build_markdown({ "title" => "X" }, [])
    assert_match "Kein offizielles TED-Transkript verfügbar", md
    refute_match "## Transkript", md
  end
end
