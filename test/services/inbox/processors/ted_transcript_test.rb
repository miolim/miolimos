require "test_helper"

# #778: TED-Importer-Processor — End-to-End mit gestubbtem HTML-Fetch.
class Inbox::Processors::TedTranscriptTest < ActiveSupport::TestCase
  setup do
    @hans = create_human
    grant(@hans, "KnowledgeItem", %w[read create update delete])
    @url = "https://www.ted.com/talks/jane_doe_my_talk"
  end

  NEXT_JSON = {
    "props" => { "pageProps" => {
      "videoData" => {
        "id" => "999", "title" => "Mein TED-Talk", "presenterDisplayName" => "Jane Doe",
        "duration" => 75, "recordedOn" => "2019-05-01", "publishedAt" => "2019-06-01T00:00:00Z",
        "description" => "Worum es geht.", "canonicalUrl" => "https://www.ted.com/talks/jane_doe_my_talk",
        "internalLanguageCode" => "en", "topics" => { "nodes" => [{ "name" => "design" }] }
      },
      "transcriptData" => { "translation" => { "paragraphs" => [
        { "cues" => [{ "text" => "Erster Satz.", "time" => 0 }] },
        { "cues" => [{ "text" => "Zweiter.", "time" => 40000 }] }
      ] } }
    } }
  }.freeze

  def fixture_html
    %(<script id="__NEXT_DATA__" type="application/json">#{JSON.generate(NEXT_JSON)}</script>)
  end

  def with_fetch_stub(html)
    original = Inbox::Processors::WebClip.instance_method(:fetch_html)
    Inbox::Processors::WebClip.define_method(:fetch_html) { |_url, **| html }
    yield
  ensure
    Inbox::Processors::WebClip.define_method(:fetch_html, original)
  end

  test "applies? / ted_talk_url? erkennt TED-Talk-URLs" do
    p = Inbox::Processors::TedTranscript
    assert p.ted_talk_url?("https://www.ted.com/talks/foo_bar")
    assert p.ted_talk_url?("https://ted.com/talks/foo")
    refute p.ted_talk_url?("https://www.ted.com/playlists/123")
    refute p.ted_talk_url?("https://example.com/talks/foo")
    refute p.ted_talk_url?(nil)
  end

  test "InboxItem mit TED-URL schlägt den TED-Importer vor (statt web_clip)" do
    item = InboxItem.new(source_kind: "web_url", source_url: @url)
    assert_equal "ted_transcript", item.suggested_processor_kind
    other = InboxItem.new(source_kind: "web_url", source_url: "https://example.com/x")
    assert_equal "web_clip", other.suggested_processor_kind
  end

  test "process! baut KI mit offiziellem Transkript + Source, kein Whisper" do
    with_isolated_miolimos_base do
      item = InboxItem.create!(source_kind: "web_url", source_url: @url,
                               payload: {}, status: "pending", creator: @hans)
      with_fetch_stub(fixture_html) do
        Current.set(actor: @hans) do
          Inbox::Processors::TedTranscript.new.process!(item, actor: @hans)
        end
      end
      ki = KnowledgeItem.find(item.reload.result["created"].first["uuid"])
      body = FileProxy.read_body(actor: @hans, knowledge_item: ki)
      assert_equal "Mein TED-Talk", ki.title
      assert_match "**Sprecher:** Jane Doe", body
      assert_match "## Transkript (TED, offiziell)", body
      assert_match "[0:00](https://www.ted.com/talks/jane_doe_my_talk#t=0) Erster Satz.", body
      assert_match "[0:40](https://www.ted.com/talks/jane_doe_my_talk#t=40) Zweiter.", body
      assert_includes ki.tags, "ted"
      assert_equal 0, LlmActivity.count, "TED-Import nutzt kein LLM/Whisper"

      src = Source.find(ki.bib_source_id)
      assert_equal "ted-999", src.slug
      assert_equal "TED", src.publisher
    end
  end
end
