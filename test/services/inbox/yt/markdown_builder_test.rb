require "test_helper"

class Inbox::Yt::MarkdownBuilderTest < ActiveSupport::TestCase
  M = Inbox::Yt::MarkdownBuilder

  test "build assembles kanal, dauer, summary, transcript heading and body" do
    md = M.build(
      { "title" => "T", "uploader" => "Kanal X",
        "duration" => 720, "upload_date" => "20240601",
        "description" => "Beschreibung." },
      "Roher Text",
      whisper_used: true, structured: true,
      summary: "- Punkt 1\n- Punkt 2"
    )
    assert_match "**Kanal:** Kanal X",                    md
    assert_match "**Dauer:** 12:00",                       md
    assert_match "**Veröffentlicht:** 2024-06-01",         md
    assert_match "## Zusammenfassung",                     md
    assert_match "- Punkt 1",                              md
    assert_match "## Transkript (Whisper, strukturiert)",  md
    assert_match "Roher Text",                             md
  end

  test "build without transcript shows the no-transcript hint" do
    md = M.build({ "title" => "T" }, "")
    assert_match "Kein Transkript verfügbar", md
  end

  test "build picks the right transcript heading for whisper-raw vs. structured vs. unknown" do
    base = { "title" => "T" }
    assert_match "## Transkript (Whisper, strukturiert)", M.build(base, "x", whisper_used: true, structured: true)
    assert_match "## Transkript (Whisper)",               M.build(base, "x", whisper_used: true, structured: false)
    assert_match "## Transkript",                          M.build(base, "x", whisper_used: false, structured: false)
  end

  # #660: Zeitstempel-Variante bekommt eine eigene Überschrift, mit Vorrang.
  test "build: timestamped-Heading hat Vorrang vor structured" do
    base = { "title" => "T" }
    assert_match "## Transkript (Whisper, mit Zeitstempeln)",
                 M.build(base, "[0:00](u) x", whisper_used: true, timestamped: true)
    assert_match "## Transkript (Whisper, mit Zeitstempeln)",
                 M.build(base, "[0:00](u) x", whisper_used: true, structured: true, timestamped: true)
  end

  test "format_duration handles hours, minutes, seconds and nil" do
    assert_equal "",        M.format_duration(nil)
    assert_equal "0:30",    M.format_duration(30)
    assert_equal "5:00",    M.format_duration(300)
    assert_equal "1:05:30", M.format_duration(3930)
  end

  test "format_date converts YYYYMMDD to ISO and falls back on garbage" do
    assert_equal "2024-06-01", M.format_date("20240601")
    assert_equal "",            M.format_date("")
    assert_equal "abcdefgh",    M.format_date("abcdefgh")
  end

  test "language_hint prefers language over original_language and ignores automatic_captions" do
    assert_equal "de", M.language_hint({ "language" => "de-DE" })
    assert_equal "en", M.language_hint({ "original_language" => "en", "language" => nil })
    assert_nil         M.language_hint({ "automatic_captions" => { "de" => [] } })
    assert_nil         M.language_hint({})
  end
end
