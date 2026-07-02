require "test_helper"

class LlmActivityTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @hans = create_human
  end

  test "track wraps a successful block as queued -> running -> succeeded" do
    result = LlmActivity.track(
      kind: :paragraph_research, actor: @hans,
      source_kind: "knowledge_item", source_id: "abc#a1",
      input_summary: "ein Absatz", model: "claude-opus-4-7"
    ) do |activity|
      assert_equal "running", activity.reload.status
      assert activity.started_at.present?
      "die Antwort"
    end

    assert_equal "die Antwort", result
    a = LlmActivity.last
    assert_equal "succeeded",        a.status
    assert_equal "die Antwort",      a.output_summary
    assert_equal "ein Absatz",       a.input_summary
    assert_equal "knowledge_item",   a.source_kind
    assert_equal "abc#a1",           a.source_id
    assert_equal "claude-opus-4-7",  a.model
    assert a.completed_at.present?
  end

  test "track unpacks a Hash result into output, result_kind, result_id" do
    LlmActivity.track(kind: :paragraph_research, actor: @hans) do
      { output: "Antwort", result_kind: "knowledge_item", result_id: "uuid-123" }
    end
    a = LlmActivity.last
    assert_equal "Antwort",        a.output_summary
    assert_equal "knowledge_item", a.result_kind
    assert_equal "uuid-123",       a.result_id
  end

  test "track unpacks token counters from Hash result" do
    LlmActivity.track(kind: :paragraph_research, actor: @hans) do
      { output: "x", input_tokens: 42, output_tokens: 17 }
    end
    a = LlmActivity.last
    assert_equal 42, a.input_tokens
    assert_equal 17, a.output_tokens
  end

  test "track captures exceptions as failed and re-raises" do
    assert_raises(RuntimeError) do
      LlmActivity.track(kind: :paragraph_research, actor: @hans) do
        raise "boom"
      end
    end
    a = LlmActivity.last
    assert_equal "failed", a.status
    assert_match "boom", a.error_message
    assert_match "RuntimeError", a.error_message
  end

  test "track truncates long inputs and outputs to 2000 chars" do
    long = "x" * 5_000
    LlmActivity.track(kind: :paragraph_research, actor: @hans, input_summary: long) do
      long
    end
    a = LlmActivity.last
    assert_equal 2_000, a.input_summary.length
    assert_equal 2_000, a.output_summary.length
  end

  test "duration_seconds returns nil before completed_at, integer after" do
    a = LlmActivity.create!(
      kind: "paragraph_research", actor: @hans, status: "queued"
    )
    assert_nil a.duration_seconds
    a.update!(started_at: 5.seconds.ago, completed_at: Time.current)
    assert_kind_of Integer, a.duration_seconds
    assert a.duration_seconds >= 4
  end

  test "validates kind and status against whitelist" do
    a = LlmActivity.new(kind: "bogus", status: "queued", actor: @hans)
    refute a.valid?
    assert_includes a.errors.attribute_names, :kind

    a = LlmActivity.new(kind: "paragraph_research", status: "weird", actor: @hans)
    refute a.valid?
    assert_includes a.errors.attribute_names, :status
  end

  test "retry! enqueues ParagraphResearchJob for paragraph_research kind" do
    a = LlmActivity.create!(
      kind: "paragraph_research", actor: @hans, status: "failed",
      source_kind: "knowledge_item", source_id: "ki-uuid#anchor-x"
    )
    assert_enqueued_with(job: ParagraphResearchJob,
                         args: ["ki-uuid", "anchor-x", "", @hans.id]) do
      assert_equal true, a.retry!
    end
  end

  test "retry! returns false when paragraph_research source_id is malformed" do
    a = LlmActivity.create!(
      kind: "paragraph_research", actor: @hans, status: "failed",
      source_kind: "knowledge_item", source_id: "no-anchor-here"
    )
    assert_no_enqueued_jobs do
      assert_equal false, a.retry!
    end
  end

  test "retry! returns false when InboxItem source no longer exists" do
    a = LlmActivity.create!(
      kind: "inbox_ai_transform", actor: @hans, status: "failed",
      source_kind: "inbox_item", source_id: "999999"
    )
    assert_no_enqueued_jobs do
      assert_equal false, a.retry!
    end
  end

  test "retry! returns false for unknown kind" do
    a = LlmActivity.new(
      kind: "paragraph_research", actor: @hans, status: "failed",
      source_kind: "knowledge_item", source_id: "ki#x"
    )
    a.save!(validate: false)
    a.update_columns(kind: "unknown_kind")
    assert_equal false, a.retry!
  end
end
