require "test_helper"

# #1675: Der Controller setzt den Eintrag VOR dem Einreihen auf „processing"
# (optimistische Anzeige). Drei Ausgänge ließen ihn dort für immer stehen — die
# Ansicht zeigt für diesen Status nur den Warte-Kreisel, keinen Knopf:
#   1. der Akteur existiert nicht mehr        → der Job kehrte still zurück
#   2. unbekannter Prozessor                  → raise, Status blieb
#   3. der Worker stirbt mitten im Lauf       → z.B. bei JEDEM Deploy
class ProcessInboxItemJobTest < ActiveSupport::TestCase
  setup do
    @hans = create_human
    @item = InboxItem.create!(creator: @hans, source_kind: "text", source_url: "",
                              raw_content: "x", status: "processing", processor_kind: "egal")
  end

  test "unbekannter Prozessor: der Eintrag wird sichtbar fehlgeschlagen, nicht ewig wartend" do
    ProcessInboxItemJob.perform_now(@item.id, "gibt_es_nicht", @hans.id)

    @item.reload
    assert_equal "failed", @item.status
    assert_match(/gibt_es_nicht/, @item.error_message)
  end

  test "geloeschter Akteur: der Eintrag wird sichtbar fehlgeschlagen" do
    ProcessInboxItemJob.perform_now(@item.id, "egal", -1)

    @item.reload
    assert_equal "failed", @item.status
    assert @item.error_message.present?
  end

  test "geloeschter Eintrag: der Job kehrt still zurueck" do
    @item.destroy!
    assert_nothing_raised { ProcessInboxItemJob.perform_now(@item.id, "egal", @hans.id) }
  end

  # ── der Aufräumer für Fall 3 ────────────────────────────────────────────

  test "Aufraeumer: was seit Stunden auf processing steht, wird fehlgeschlagen — Frisches bleibt" do
    alt    = @item
    alt.update_columns(updated_at: 4.hours.ago)
    frisch = InboxItem.create!(creator: @hans, source_kind: "text", source_url: "",
                               raw_content: "y", status: "processing")
    fertig = InboxItem.create!(creator: @hans, source_kind: "text", source_url: "",
                               raw_content: "z", status: "processed")
    fertig.update_columns(updated_at: 4.hours.ago)

    InboxStuckReaperJob.perform_now

    assert_equal "failed", alt.reload.status
    assert_match(/erneut/i, alt.error_message)
    assert_equal "processing", frisch.reload.status
    assert_equal "processed",  fertig.reload.status
  end

  test "der Aufraeumer ist im Produktiv-Zeitplan eingetragen" do
    plan = YAML.load_file(Rails.root.join("config/recurring.yml"))
    assert_equal "InboxStuckReaperJob", plan.dig("production", "inbox_stuck_reaper", "class")
  end
end
