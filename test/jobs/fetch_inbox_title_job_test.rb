require "test_helper"

# #203: Coverage fuer FetchInboxTitleJob — Early-Returns und
# pure-Function-Pfade direkt. HTTP-/Subprocess-Pfade nicht End-to-End.
class FetchInboxTitleJobTest < ActiveJob::TestCase
  setup do
    @hans = create_human
  end

  test "perform: unbekanntes InboxItem → kein Fehler, kein Update" do
    assert_nothing_raised { FetchInboxTitleJob.new.perform(999_999) }
  end

  test "perform: payload['title'] schon gesetzt → kein Overwrite" do
    item = InboxItem.create!(creator: @hans, source_kind: "web_url",
                              source_url: "https://example.com",
                              payload: { "title" => "Schon da" },
                              status: "pending")
    FetchInboxTitleJob.new.perform(item.id)
    assert_equal "Schon da", item.reload.payload["title"]
  end

  test "perform: leere source_url → kein Update" do
    item = InboxItem.create!(creator: @hans, source_kind: "text",
                              source_url: "",
                              raw_content: "x", status: "pending")
    FetchInboxTitleJob.new.perform(item.id)
    assert_nil item.reload.payload["title"]
  end

  # #618 v3: Der Job referenzierte YoutubeTranscribe::YT_BIN — die
  # Konstante gab es nie (richtig: Inbox::Yt::YtDlp::BIN). Das rescue
  # schluckte den NameError, YouTube-Titel kamen deshalb nie an. Dieser
  # Test läuft durch die Konstanten-Auflösung (Open3 gestubbt).
  test "fetch_youtube_title: Binary-Konstante existiert, Titel landet im payload" do
    item = InboxItem.create!(creator: @hans, source_kind: "youtube_url",
                              source_url: "https://www.youtube.com/watch?v=abc12345678",
                              status: "pending")
    ok = Object.new
    def ok.success? = true
    # Open3 von Hand stubben — minitest/mock ist in Minitest 6 ein
    # eigenes (hier nicht gebundeltes) Gem.
    original = Open3.method(:capture3)
    Open3.define_singleton_method(:capture3) { |*_a| ["Video-Titel\n", "", ok] }
    begin
      FetchInboxTitleJob.new.perform(item.id)
    ensure
      Open3.define_singleton_method(:capture3, original)
    end
    assert_equal "Video-Titel", item.reload.payload["title"]
  end

  test "fetch_html_title fängt non-HTTP-Schema ab" do
    job = FetchInboxTitleJob.new
    assert_nil job.send(:fetch_html_title, "file:///etc/hosts")
    assert_nil job.send(:fetch_html_title, "ftp://example.com")
  end

  test "decode_html_entities handhabt die haeufigsten Entities" do
    job = FetchInboxTitleJob.new
    assert_equal "A & B \"C\" 'D' E",
                 job.send(:decode_html_entities, "A &amp; B &quot;C&quot; &#39;D&#39; E")
    assert_equal "ä",
                 job.send(:decode_html_entities, "&#228;")
  end
end
