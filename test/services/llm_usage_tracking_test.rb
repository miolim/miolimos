require "test_helper"

# #628 W0: Token-/Kosten-Tracking — record_usage schreibt Anthropic-Usage
# an die LlmActivity, Whisper rechnet über die Audiolänge ab.
class LlmUsageTrackingTest < ActiveSupport::TestCase
  setup do
    @hans = HumanActor.create!(name: "Hans", email: "hans-llm-#{SecureRandom.hex(3)}@t.local",
                               password: "secretsecret")
  end

  def activity
    LlmActivity.create!(kind: "inbox_youtube_structure", actor: @hans, status: "running")
  end

  test "record_usage schreibt Tokens und EUR-Kosten (Haiku-Preise)" do
    a = activity
    Llm::ChatClient.record_usage(a, "claude-haiku-4-5",
                                 { "input_tokens" => 100_000, "output_tokens" => 10_000 })
    a.reload
    assert_equal 100_000, a.input_tokens
    assert_equal 10_000,  a.output_tokens
    # (100k × 1$/M + 10k × 5$/M) × Kurs
    expected = (0.1 + 0.05) * Llm::ChatClient::USD_EUR_RATE
    assert_in_delta expected, a.cost_eur.to_f, 0.000001
  end

  test "record_usage: unbekanntes Modell → Tokens ja, Kosten nil" do
    a = activity
    Llm::ChatClient.record_usage(a, "totally-unknown-model",
                                 { "input_tokens" => 5, "output_tokens" => 7 })
    a.reload
    assert_equal 5, a.input_tokens
    assert_nil a.cost_eur
  end

  test "record_usage schluckt kaputte Inputs ohne Exception" do
    assert_nothing_raised do
      Llm::ChatClient.record_usage(nil, "claude-haiku-4-5", { "input_tokens" => 1 })
      Llm::ChatClient.record_usage(activity, "claude-haiku-4-5", nil)
      Llm::ChatClient.record_usage(activity, nil, "kein hash")
    end
  end

  test "whisper_cost_eur rechnet über die Audiominuten" do
    t = Inbox::Yt::WhisperTranscriber.new(actor: @hans)
    # 10 Minuten × 0,006 $/Min × Kurs
    expected = 10 * 0.006 * Llm::ChatClient::USD_EUR_RATE
    assert_in_delta expected, t.send(:whisper_cost_eur, 600.0), 0.000001
    assert_nil t.send(:whisper_cost_eur, nil)
    assert_nil t.send(:whisper_cost_eur, 0)
  end
end
