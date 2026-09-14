require "test_helper"

# #1586 (Hans): Poke während der Agent arbeitet — „OK, dann bitte so bauen."
#
# Regel a: Antwort auf die Aufgabe, an der der Agent gerade sitzt (WIP) →
# sofort. Alles andere → Auslöser sofort setzen, eintippen erst, wenn die
# Sitzung ruhig ist (DeferredInboxPokeJob).
class BuilderInboxPokeDeferTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  # send_tmux zählen, Sitzungszustand vorgeben — kein echtes tmux.
  class Probe < BuilderInboxPoke
    attr_reader :sends
    attr_writer :busy
    def initialize(**kw)
      super(**kw)
      @sends = 0
      @busy  = false
    end
    def send_tmux = (@sends += 1)
    def session_busy? = @busy
  end

  setup do
    @agent = create_agent
    @hans  = create_human
  end

  def poke(busy:, task: nil, sofort: false, debounce: true)
    p = Probe.new(actor: @agent, note: "Test", debounce: debounce, task: task, sofort: sofort)
    p.busy = busy
    [p.call, p.sends]
  end

  test "ruhige Sitzung: sofort eintippen" do
    ok, sends = poke(busy: false)
    assert ok
    assert_equal 1, sends
    assert_no_enqueued_jobs only: DeferredInboxPokeJob
  end

  test "beschäftigte Sitzung: Flag sofort, Eintippen aufgeschoben" do
    ok, sends = poke(busy: true)
    assert ok
    assert_equal 0, sends
    assert_not_nil @agent.reload.inbox_run_requested_at, "der Auslöser gilt sofort"
    assert_enqueued_jobs 1, only: DeferredInboxPokeJob
  end

  test "Antwort auf die eigene WIP-Aufgabe: sofort, auch wenn beschäftigt" do
    task = Task.create!(title: "Laufend", creator: @hans, assignee: @agent, status: :open, wip_actor_id: @agent.id)
    _ok, sends = poke(busy: true, task: task)
    assert_equal 1, sends
    assert_no_enqueued_jobs only: DeferredInboxPokeJob
  end

  test "Antwort auf eine andere Aufgabe: aufgeschoben" do
    task = Task.create!(title: "Andere", creator: @hans, assignee: @agent, status: :open)
    _ok, sends = poke(busy: true, task: task)
    assert_equal 0, sends
    assert_enqueued_jobs 1, only: DeferredInboxPokeJob
  end

  test "Trigger-Knopf (sofort) tippt immer" do
    _ok, sends = poke(busy: true, sofort: true, debounce: false)
    assert_equal 1, sends
  end

  test "Beschäftigt-Erkennung an echten Fußzeilen" do
    arbeitet = "Running 1 shell command · 18s…\n  ⏵⏵ bypass permissions on (shift+tab to cycle) · esc to interrupt"
    wartet   = "✻ Brewed for 39s · done 6:27 · 1 shell still running\n❯ \n  ⏵⏵ bypass permissions on · 1 shell · ← for agents · ↓ to manage"
    assert BuilderInboxPoke.busy_pane?(arbeitet)
    assert_not BuilderInboxPoke.busy_pane?(wartet), "Warten auf Hintergrund-Lauf zählt als ruhig"
    assert_not BuilderInboxPoke.busy_pane?(nil)
  end

  # ─── Job ────────────────────────────────────────────────────────────────

  def flag!(at = 2.minutes.ago)
    t = at.floor(6)
    @agent.update_columns(inbox_run_requested_at: t, last_seen_at: 10.minutes.ago)
    t.iso8601(6)
  end

  # Sitzung und tmux ersetzen — Minitest 6 hat kein `stub` mehr.
  class JobProbe < DeferredInboxPokeJob
    attr_accessor :busy
    def getippt = (@getippt ||= [])
    def busy?(_actor) = busy
    def tippen(actor, note) = getippt << [actor.id, note]
  end

  def run_job(requested_at, busy:, geplant_at: Time.current)
    job = JobProbe.new
    job.busy = busy
    job.perform(@agent.id, "Neue Antwort", requested_at, geplant_at.iso8601)
    job.getippt
  end

  test "Job tippt, sobald die Sitzung ruhig ist" do
    assert_equal [[@agent.id, "Neue Antwort"]], run_job(flag!, busy: false)
  end

  test "Job wartet weiter, solange beschäftigt" do
    requested = flag!
    assert_empty run_job(requested, busy: true)
    assert_enqueued_jobs 1
  end

  test "Job tippt nach der Obergrenze trotzdem" do
    requested = flag!
    getippt = run_job(requested, busy: true, geplant_at: (BuilderInboxPoke::DEFER_MAX + 1.minute).ago)
    assert_equal 1, getippt.size
  end

  test "Job verwirft sich, wenn der Agent den Auslöser schon geholt hat" do
    requested = flag!
    @agent.update_columns(inbox_run_requested_at: nil, last_seen_at: Time.current)
    assert_empty run_job(requested, busy: false)
  end

  test "Job verwirft sich, wenn der Heartbeat nach dem Poke kam" do
    requested = flag!
    @agent.update_column(:last_seen_at, 1.minute.ago)
    assert_empty run_job(requested, busy: false)
  end

  test "Job verwirft sich, wenn ein neuerer Poke das Flag überschrieben hat" do
    requested = flag!(3.minutes.ago)
    flag!(1.minute.ago)
    assert_empty run_job(requested, busy: false)
  end
end
