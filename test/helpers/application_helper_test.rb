require "test_helper"

class ApplicationHelperTest < ActionView::TestCase
  test "audit_log_summary renders human-readable message for status change" do
    hans  = create_human
    topic = create_topic(creator: hans)
    log = AuditLog.create!(actor: hans, auditable: topic, action: "updated",
                            changes_data: { "status" => ["open", "done"] })
    text = audit_log_summary(log)
    assert_includes text, hans.name
    assert_includes text, "Status"
  end

  test "audit_log_summary handles created action" do
    hans  = create_human
    topic = create_topic(creator: hans)
    log = AuditLog.create!(actor: hans, auditable: topic, action: "created")
    assert_includes audit_log_summary(log), "angelegt"
  end

  # ─── compact_age ─────────────────────────────────────────────────────

  test "compact_age liefert leer für nil" do
    assert_equal "", compact_age(nil)
  end

  test "compact_age liefert '<1m' für gerade-eben" do
    assert_equal "<1m", compact_age(30.seconds.ago)
  end

  test "compact_age skaliert m/h/d/w/y" do
    assert_match(/^\d+m$/, compact_age(5.minutes.ago))
    assert_match(/^\d+h$/, compact_age(2.hours.ago))
    assert_match(/^\d+d$/, compact_age(3.days.ago))
    assert_match(/^\d+w$/, compact_age(2.weeks.ago))
    assert_match(/^\d+y$/, compact_age(2.years.ago))
  end

  # ─── chat_import_prompt ─────────────────────────────────────────────

  test "chat_import_prompt liefert Default wenn kein Setting" do
    Setting.where(key: "chat_import_prompt").destroy_all
    assert_equal ApplicationHelper::CHAT_IMPORT_PROMPT_DEFAULT, chat_import_prompt
  end

  test "chat_import_prompt liefert Custom-Setting wenn gesetzt" do
    Setting.set("chat_import_prompt", "Mein Custom-Prompt")
    assert_equal "Mein Custom-Prompt", chat_import_prompt
  ensure
    Setting.where(key: "chat_import_prompt").destroy_all
  end

  # ─── sidebar_link (#856) ─────────────────────────────────────────────
  # Das Label wird im Collapse NUR auf Desktop (md+) ausgeblendet — auf
  # Mobile ist die Sidebar ein Voll-Overlay und die Bezeichnungen sollen
  # immer sichtbar bleiben. Regressionsschutz gegen die nackte (all-
  # breakpoint) hidden-Variante, die mobil die Labels verschluckt hat.
  test "sidebar_link blendet das Label nur auf Desktop (md) aus (#856)" do
    html = sidebar_link("Grundstücke", "/properties", "folder").to_s
    assert_includes html, "group-data-[collapsed=true]/sidebar:md:hidden"
    assert_includes html, "Grundstücke"
    # keine ungeschützte all-breakpoint Variante mehr am Label
    assert_no_match(/sidebar:hidden(?!:)/, html.gsub("sidebar:md:hidden", ""))
  end
end
