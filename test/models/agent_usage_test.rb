require "test_helper"

# #1660: Kostenrechnung über den verdichteten Zeilen. Die Sätze sind
# Listenpreise je Modellfamilie; Cache-Schreiben zum 1-Stunden-Satz, weil
# Claude Code genau den nutzt.
class AgentUsageTest < ActiveSupport::TestCase
  def zeile(model: "claude-opus-5", ein: 0, cache_neu: 0, cache_gelesen: 0, aus: 0)
    AgentUsage.new(tag: Date.current, projekt: "-home-hans", model: model, antworten: 1,
                   input_tokens: ein, cache_creation_tokens: cache_neu,
                   cache_read_tokens: cache_gelesen, output_tokens: aus)
  end

  test "Kosten je Token-Art nach den Saetzen der Modellfamilie" do
    z = zeile(ein: 1_000_000, cache_neu: 1_000_000, cache_gelesen: 1_000_000, aus: 1_000_000)
    k = AgentUsage.kosten_usd([z])

    assert_in_delta 15.0, k[:ein], 0.001
    assert_in_delta 30.0, k[:cache_schreiben], 0.001
    assert_in_delta 1.50, k[:cache_lesen], 0.001
    assert_in_delta 75.0, k[:aus], 0.001
    assert_in_delta 121.5, k[:gesamt], 0.001
  end

  test "Haiku ist deutlich guenstiger als Opus" do
    opus  = AgentUsage.kosten_usd([zeile(model: "claude-opus-5", aus: 1_000_000)])[:gesamt]
    haiku = AgentUsage.kosten_usd([zeile(model: "claude-haiku-4-5", aus: 1_000_000)])[:gesamt]
    assert_operator haiku, :<, opus
    assert_in_delta 5.0, haiku, 0.001
  end

  test "unbekanntes Modell kostet nichts, statt zu raten" do
    k = AgentUsage.kosten_usd([zeile(model: "irgendwas-neues", aus: 1_000_000)])
    assert_in_delta 0.0, k[:gesamt], 0.001
  end

  test "Saetze lassen sich per Umgebungsvariable ueberschreiben" do
    alt = ENV["AGENT_USAGE_PREIS_OPUS_AUS"]
    ENV["AGENT_USAGE_PREIS_OPUS_AUS"] = "60"
    assert_in_delta 60.0, AgentUsage.preise_fuer("claude-opus-5")[:aus], 0.001
    assert_in_delta 60.0, AgentUsage.kosten_usd([zeile(aus: 1_000_000)])[:gesamt], 0.001
  ensure
    alt.nil? ? ENV.delete("AGENT_USAGE_PREIS_OPUS_AUS") : ENV["AGENT_USAGE_PREIS_OPUS_AUS"] = alt
  end

  test "summe zaehlt Tokens und Kosten ueber mehrere Zeilen" do
    s = AgentUsage.summe([zeile(cache_gelesen: 1_000_000, aus: 100_000),
                          zeile(model: "claude-haiku-4-5", cache_gelesen: 2_000_000)])

    assert_equal 2, s[:antworten]
    assert_equal 3_000_000, s[:cache_lesen]
    assert_equal 100_000, s[:aus]
    # Opus: 1,50 (Cache) + 7,50 (Ausgabe) · Haiku: 0,20 (Cache)
    assert_in_delta 9.20, s[:kosten][:gesamt], 0.001
  end
end
