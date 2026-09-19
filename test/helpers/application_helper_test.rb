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

  # ── #1672: derselbe Katalog für die übrigen Bauformen ────────────────────
  #
  # Die Bauformen bleiben getrennt (sie unterscheiden sich darin, ob und wie
  # eine Anfrage rausgeht); vereinheitlicht ist die Namensseite.

  test "ui_button nimmt Symbol und Beschriftung aus dem Katalog" do
    html = ui_button(:karte_schliessen)
    assert_includes html, 'data-ui-icon="karte_schliessen"'
    assert_includes html, I18n.t("shared.close_button.close_card")
    assert_includes html, "<svg"
  end

  test "ui_button_to baut einen Knopf mit eigenem Formular" do
    html = ui_button_to(:karte_schliessen, "/irgendwo", method: :delete)
    assert_includes html, "<form"
    assert_includes html, 'data-ui-icon="karte_schliessen"'
    assert_includes html, I18n.t("shared.close_button.close_card")
  end

  test "ui_link baut einen Link mit Kennung" do
    html = ui_link(:karte_schliessen, "/irgendwo", class: "px-2 rounded")
    assert_includes html, "<a "
    assert_includes html, 'href="/irgendwo"'
    assert_includes html, 'data-ui-icon="karte_schliessen"'
  end

  # Ein Eintrag OHNE Symbol trägt seinen Namen als Text — so kommen auch die
  # beschrifteten Befehle in denselben Katalog, ohne dass man ihnen ein Symbol
  # andichten müsste.
  test "ein Eintrag ohne Symbol rendert seine Beschriftung als Text" do
    datei = Rails.root.join("config/ui_elemente.helper_test.yml")
    File.write(datei, { "nur_beschriftet_test" => { "label" => "actions.save" } }.to_yaml)
    UiElemente.neu_laden!

    html = ui_button(:nur_beschriftet_test)
    assert_includes html, I18n.t("actions.save")
    assert_not_includes html, "<svg"
  ensure
    File.delete(datei) if datei && File.exist?(datei)
    UiElemente.neu_laden!
  end

  test "eine unbekannte Kennung ist im Test ein Fehler" do
    assert_raises(UiElemente::Unbekannt) { ui_button(:gibt_es_nicht_12345) }
  end
end
