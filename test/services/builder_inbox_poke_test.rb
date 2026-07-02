require "test_helper"

# #382 (Hans, 2026-06-03): BuilderInboxPoke — Flag setzen + (gestubbter)
# tmux-Send, mit Debounce/Coalesce. Der echte tmux-Send wird gestubbt,
# damit der Test keine send-keys in eine Session schreibt.
class BuilderInboxPokeTest < ActiveSupport::TestCase
  setup do
    @agent = create_agent
  end

  # send_tmux stubben: zaehlt Aufrufe, ohne wirklich tmux anzusprechen.
  class Counting < BuilderInboxPoke
    attr_reader :sends
    def initialize(**kw)
      super(**kw)
      @sends = 0
    end
    def send_tmux = (@sends += 1)
  end

  def poke(actor: @agent, note: nil, debounce: true)
    c = Counting.new(actor: actor, note: note, debounce: debounce)
    [c.call, c.sends]
  end

  test "poke setzt das Flag und sendet" do
    ok, sends = poke
    assert ok
    assert_equal 1, sends
    assert_not_nil @agent.reload.inbox_run_requested_at
  end

  test "debounce coalesct einen zweiten Poke kurz darauf" do
    @agent.update_column(:inbox_run_requested_at, Time.current)
    ok, sends = poke(debounce: true)
    assert_not ok
    assert_equal 0, sends
  end

  test "debounce: false feuert immer (Button)" do
    @agent.update_column(:inbox_run_requested_at, Time.current)
    ok, sends = poke(debounce: false)
    assert ok
    assert_equal 1, sends
  end

  test "alter Request (jenseits Debounce) feuert wieder" do
    @agent.update_column(:inbox_run_requested_at, 2.minutes.ago)
    ok, sends = poke(debounce: true)
    assert ok
    assert_equal 1, sends
  end

  test "kein Agent -> kein Poke" do
    ok, sends = poke(actor: create_human)
    assert_not ok
    assert_equal 0, sends
  end
end
