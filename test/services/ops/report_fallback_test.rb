require "test_helper"

# #1076: Ersatzzustellung, wenn der Mailweg steht.
module Ops
  class ReportFallbackTest < ActiveSupport::TestCase
    setup do
      @actor = create_human
      grant(@actor, "KnowledgeItem", %w[read create update delete])
      @now   = Time.zone.parse("2026-07-21 09:00:00")
      @dir   = Dir.mktmpdir
      OauthCredential.where(provider: "google").delete_all
    end

    teardown { FileUtils.remove_entry(@dir) }

    def report
      backup = File.join(@dir, "backup.log")
      File.write(backup, "[2026-07-21 04:30:44] backup done (errors=0)\n")
      DailyReport.new(state_file: File.join(@dir, "fehlt"), event_log: File.join(@dir, "fehlt2"),
                      backup_log: backup, repos: {}, now: @now)
    end

    test "legt ein Wissenselement mit dem Bericht an" do
      fallback = ReportFallback.new(report, actor: @actor, reason: "GmailSender::Error: keine Credential", now: @now)

      item = nil
      assert_difference -> { KnowledgeItem.count }, +1 do
        item = fallback.deliver!
      end

      assert_equal "Betriebsbericht 21.07.2026 (Mailversand gestoert)", item.title
      body = item.body
      assert_includes body, "nicht per Mail"
      assert_includes body, "GmailSender::Error"
      assert_includes body, "Datensicherung"
      # Der Grund des Ausfalls muss als Auffaelligkeit auftauchen — sonst
      # erklaert der Ersatzbericht nicht, warum es ihn gibt.
      assert_includes body, "kein Google-Konto verbunden"
    end

    test "ohne Actor gibt es eine klare Fehlermeldung statt eines Absturzes" do
      err = assert_raises(ArgumentError) do
        ReportFallback.new(report, actor: nil, now: @now).deliver!
      end
      assert_includes err.message, "Actor"
    end
  end
end
