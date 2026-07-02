require "test_helper"

class Inbox::Yt::TranscriptPostProcessorTest < ActiveSupport::TestCase
  setup do
    @hans = create_human
    @meta = { "title" => "T", "webpage_url" => "https://yt/x" }
  end

  test "structure returns LLM output and tracks succeeded activity when long enough" do
    p = Inbox::Yt::TranscriptPostProcessor.new(actor: @hans)
    out = "x" * 800
    result = nil
    stub_chat_client(out) do
      result = p.structure("x" * 1_000, @meta)
    end
    assert_equal out, result
    a = LlmActivity.where(kind: "inbox_youtube_structure").last
    assert_equal "succeeded", a.status
  end

  test "structure marks failed and returns nil when LLM output is suspiciously short" do
    p = Inbox::Yt::TranscriptPostProcessor.new(actor: @hans)
    stub_chat_client("k") do
      assert_nil p.structure("x" * 1_000, @meta)
    end
    a = LlmActivity.where(kind: "inbox_youtube_structure").last
    assert_equal "failed", a.status
    assert_match "Output zu kurz", a.error_message
  end

  test "summarize returns LLM output and tracks succeeded activity" do
    p = Inbox::Yt::TranscriptPostProcessor.new(actor: @hans)
    result = nil
    stub_chat_client("- A\n- B\n- C") do
      result = p.summarize("transcript", @meta)
    end
    assert_equal "- A\n- B\n- C", result
    assert_equal "succeeded", LlmActivity.where(kind: "inbox_youtube_summary").last.status
  end

  test "summarize returns nil and marks failed for blank LLM output" do
    p = Inbox::Yt::TranscriptPostProcessor.new(actor: @hans)
    stub_chat_client("") do
      assert_nil p.summarize("t", @meta)
    end
    assert_equal "failed", LlmActivity.where(kind: "inbox_youtube_summary").last.status
  end

  # #660 v2: section_headings parst die `N: Titel`-Antwort, nur gültige Indizes.
  test "section_headings parst gültige Zuordnungen und ignoriert Müll" do
    p = Inbox::Yt::TranscriptPostProcessor.new(actor: @hans)
    paras = (1..6).map { |i| "[#{i}:00](u) Absatz #{i} Inhalt." }
    llm = "Hier die Gliederung:\n1: Einleitung\n3. Mittelteil\n9: Zu groß ignorieren\n5: **Schluss**"
    res = nil
    stub_chat_client(llm) do
      res = p.section_headings(paras, @meta)
    end
    assert_equal({ 1 => "Einleitung", 3 => "Mittelteil", 5 => "Schluss" }, res)
  end

  # #801 P1: Fehlerpfade — alle Pässe sind best effort und dürfen bei
  # LLM-Ausfall nie eine Exception nach außen lassen.
  test "structure returns nil when the LLM is unavailable" do
    p = Inbox::Yt::TranscriptPostProcessor.new(actor: @hans)
    stub_chat_client(->(**_) { raise Llm::ChatClient::UnavailableError, "down" }) do
      assert_nil p.structure("x" * 100, @meta)
    end
  end

  test "section_headings returns {} when the LLM is unavailable" do
    p = Inbox::Yt::TranscriptPostProcessor.new(actor: @hans)
    paras = (1..4).map { |i| "Absatz #{i}" }
    stub_chat_client(->(**_) { raise Llm::ChatClient::UnavailableError, "down" }) do
      assert_equal({}, p.section_headings(paras, @meta))
    end
  end

  test "section_headings: zu kurzes Transkript ruft die KI gar nicht" do
    p = Inbox::Yt::TranscriptPostProcessor.new(actor: @hans)
    called = false
    stub_chat_client(->(**_) { called = true; "1: X" }) do
      assert_equal({}, p.section_headings(["a", "b"], @meta))
    end
    refute called
  end
end
