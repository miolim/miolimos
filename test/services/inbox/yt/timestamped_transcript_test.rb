require "test_helper"

# #660: Zeitstempel-Absätze aus Whisper-Segmenten.
class TimestampedTranscriptTest < ActiveSupport::TestCase
  T = Inbox::Yt::TimestampedTranscript

  def seg(start, ende, text)
    { "start" => start.to_f, "end" => ende.to_f, "text" => text }
  end

  def link
    ->(sec) { "https://www.youtube.com/watch?v=ABC&t=#{sec}s" }
  end

  test "format_ts: MM:SS unter einer Stunde, H:MM:SS darüber" do
    assert_equal "0:05",    T.format_ts(5)
    assert_equal "1:30",    T.format_ts(90)
    assert_equal "1:00:00", T.format_ts(3600)
    assert_equal "2:03:09", T.format_ts(7389)
  end

  test "build: ein Absatz pro Satzgrenze ab MIN_PARA_SECONDS, mit Zeitstempel-Link" do
    segments = [
      seg(0,  10, "Erster Satz beginnt hier"),
      seg(10, 20, "und geht weiter"),
      seg(20, 35, "und endet jetzt."),      # 35s, Satzende → Absatz 1 schließt
      seg(35, 45, "Zweiter Absatz startet"),
      seg(45, 70, "und endet hier auch.")   # 35s ab 35 → Absatz 2
    ]
    md = T.build(segments, link_for: link)
    paras = md.split("\n\n")
    assert_equal 2, paras.size
    assert_match %r{\A\[0:00\]\(https://www\.youtube\.com/watch\?v=ABC&t=0s\) Erster Satz}, paras[0]
    assert_includes paras[0], "und endet jetzt."
    assert_match %r{\A\[0:35\]\(https://www\.youtube\.com/watch\?v=ABC&t=35s\) Zweiter Absatz}, paras[1]
  end

  test "build: harter Schnitt nach MAX_PARA_SECONDS auch ohne Satzende" do
    segments = (0..120).step(10).map { |t| seg(t, t + 10, "wort um wort ohne punkt") }
    md = T.build(segments, link_for: link)
    paras = md.split("\n\n")
    # 130s Material, Cap bei 90s → mind. 2 Absätze.
    assert paras.size >= 2, "erwarte Aufteilung bei MAX_PARA_SECONDS, hatte #{paras.size}"
    assert paras.first.start_with?("[0:00]")
  end

  # #660 v2: H3-Überschriften zwischen Absätze weben, Zeitstempel unberührt.
  test "weave: Überschriften an den richtigen Stellen, Absätze unverändert" do
    paras = ["[0:00](u1) Erster Absatz.", "[1:30](u2) Zweiter.", "[3:00](u3) Dritter."]
    md = T.weave(paras, { 1 => "Einleitung", 3 => "Hauptteil" })
    assert_equal "### Einleitung\n\n[0:00](u1) Erster Absatz.\n\n[1:30](u2) Zweiter.\n\n### Hauptteil\n\n[3:00](u3) Dritter.", md
  end

  test "weave: leere/nil Headings → reine Absätze" do
    paras = ["[0:00](u) A.", "[1:00](u) B."]
    assert_equal "[0:00](u) A.\n\n[1:00](u) B.", T.weave(paras, nil)
    assert_equal "[0:00](u) A.\n\n[1:00](u) B.", T.weave(paras, { 1 => "  " })
  end

  test "build: leere Eingabe → leerer String, Whitespace wird normalisiert" do
    assert_equal "", T.build([], link_for: link)
    md = T.build([seg(0, 40, "  doppelte   Spaces   und   Satzende.  ")], link_for: link)
    assert_includes md, "doppelte Spaces und Satzende."
    refute_includes md, "  "
  end

  # #776: Sprecher-Absätze aus Utterances.
  test "speaker_paragraphs: Zeitstempel-Link + fettes Sprecher-Label, leere raus" do
    utts = [
      { "speaker" => "A", "start" => 0.0,  "text" => "Hallo zusammen." },
      { "speaker" => "B", "start" => 65.4, "text" => "Freut mich." },
      { "speaker" => "A", "start" => 80.0, "text" => "   " }
    ]
    paras = T.speaker_paragraphs(utts, link_for: link)
    assert_equal 2, paras.size, "leere Utterance muss rausfallen"
    assert_equal "[0:00](https://www.youtube.com/watch?v=ABC&t=0s) **Sprecher A:** Hallo zusammen.", paras[0]
    assert_equal "[1:05](https://www.youtube.com/watch?v=ABC&t=65s) **Sprecher B:** Freut mich.", paras[1]
  end

  # #776 v2: langer Turn mit Wort-Zeitstempeln → mehrere Absätze + Stempel.
  test "speaker_paragraphs: langer Turn wird per Wort-Timings in Absätze zerlegt" do
    words = []
    (0..8).each  { |i| words << { "start" => i * 5.0, "end" => i * 5.0 + 4, "text" => (i == 8 ? "eins." : "wort") } }
    (9..25).each { |i| words << { "start" => i * 5.0, "end" => i * 5.0 + 4, "text" => (i == 25 ? "zwei." : "wort") } }
    utts  = [{ "speaker" => "A", "start" => 0.0, "text" => "voller turn text", "words" => words }]
    paras = T.speaker_paragraphs(utts, link_for: link)

    assert_operator paras.size, :>=, 2, "langer Turn muss in mehrere Absätze zerfallen"
    assert_includes paras[0], "**Sprecher A:**", "erster Absatz trägt das Sprecher-Label"
    assert paras[0].start_with?("[0:00]"), "erster Absatz startet bei 0:00"
    refute_includes paras[1], "Sprecher", "Fortsetzung ohne wiederholtes Label"
    assert_match(/\A\[\d/, paras[1], "Fortsetzung hat eigenen Zeitstempel-Link")
    refute paras[1].start_with?("[0:00]"), "Fortsetzung hat einen späteren Stempel"
  end

  test "speaker_paragraphs: ohne Wort-Timings unverändert ein Absatz (Fallback)" do
    utts  = [{ "speaker" => "A", "start" => 12.0, "text" => "Nur ein Satz." }]
    paras = T.speaker_paragraphs(utts, link_for: link)
    assert_equal ["[0:12](https://www.youtube.com/watch?v=ABC&t=12s) **Sprecher A:** Nur ein Satz."], paras
  end
end
