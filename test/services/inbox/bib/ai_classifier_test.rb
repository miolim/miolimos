require "test_helper"

class Inbox::Bib::AiClassifierTest < ActiveSupport::TestCase
  def stub_chat(raw)
    orig_complete = Llm::ChatClient.method(:complete)
    orig_detect   = Llm::ChatClient.method(:detect_provider)
    Llm::ChatClient.define_singleton_method(:detect_provider) { :anthropic }
    Llm::ChatClient.define_singleton_method(:complete) { |**_| raw }
    yield
  ensure
    Llm::ChatClient.define_singleton_method(:complete, orig_complete)
    Llm::ChatClient.define_singleton_method(:detect_provider, orig_detect)
  end

  test "ohne LLM-Provider → nil" do
    orig = Llm::ChatClient.method(:detect_provider)
    Llm::ChatClient.define_singleton_method(:detect_provider) { nil }
    begin
      assert_nil Inbox::Bib::AiClassifier.call(text: "anything")
    ensure
      Llm::ChatClient.define_singleton_method(:detect_provider, orig)
    end
  end

  test "extrahiert Felder aus reinem JSON-Output" do
    raw = '{"type":"article-journal","title":"X","authors":[{"given":"A","family":"B"}],"year":2024,"doi":"10.1/x"}'
    stub_chat(raw) do
      out = Inbox::Bib::AiClassifier.call(text: "snippet")
      assert_equal "X", out[:title]
      assert_equal "article-journal", out[:csl_type]
      assert_equal Date.new(2024, 1, 1), out[:issued_date]
      assert_equal "DOI", out[:identifier][:scheme]
      assert_equal "10.1/x", out[:identifier][:value]
      assert_equal [{ given: "A", family: "B" }], out[:authors]
    end
  end

  test "verträgt ```json …```-Codeblock-Umrandung" do
    raw = "```json\n{\"title\":\"Y\",\"year\":2020}\n```"
    stub_chat(raw) do
      out = Inbox::Bib::AiClassifier.call(text: "snippet")
      assert_equal "Y", out[:title]
      assert_equal Date.new(2020, 1, 1), out[:issued_date]
    end
  end

  test "fällt bei kaputtem JSON sauber auf nil zurück" do
    stub_chat("not json at all") do
      assert_nil Inbox::Bib::AiClassifier.call(text: "snippet")
    end
  end
end
