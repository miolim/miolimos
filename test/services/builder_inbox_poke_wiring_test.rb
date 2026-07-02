require "test_helper"

# #639: Verdrahtungs-Parser — Crontab-Zeile mit (id=)-Marker, auch
# auskommentiert (die Zeile ist seit #441 reine Poke-Registry).
class BuilderInboxPokeWiringTest < ActiveSupport::TestCase
  CRONTAB = <<~CRON
    0 * * * * /home/hans/bin/push.sh
    # [deaktiviert] */10 * * * * tmux send-keys -t miolim -l 'Inbox-Check für miolim_builder (id=6). Heartbeat …' && sleep 1 && tmux send-keys -t miolim Enter
    # */10 * * * * tmux send-keys -t miolim-researcher 'Inbox-Check für miolim Researcher (id=7). Schritte wie im Memory-File.' Enter
  CRON

  test "parse_wiring findet Session + Prompt, auch in Kommentarzeilen" do
    session, prompt = BuilderInboxPoke.parse_wiring(CRONTAB, 6)
    assert_equal "miolim", session
    assert_includes prompt, "Inbox-Check für miolim_builder (id=6)"

    session7, = BuilderInboxPoke.parse_wiring(CRONTAB, 7)
    assert_equal "miolim-researcher", session7
  end

  test "parse_wiring ohne Marker-Zeile → nil" do
    assert_nil BuilderInboxPoke.parse_wiring(CRONTAB, 99)
    assert_nil BuilderInboxPoke.parse_wiring(nil, 6)
  end
end
