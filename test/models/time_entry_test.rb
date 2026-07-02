require "test_helper"

# #533 Phase 1 (Hans, 2026-06-07): Zeitbuchung — Timer-Lebenszyklus,
# Ein-Timer-Regel, Dauer, polymorpher Inhaltsbezug.
class TimeEntryTest < ActiveSupport::TestCase
  setup do
    @hans  = create_human
    @topic = create_topic(creator: @hans)
    @task  = create_task(creator: @hans)
  end

  def person_ki(name = "Kunde GmbH")
    KnowledgeItem.create!(
      uuid: SecureRandom.uuid, title: name, item_type: :organization,
      file_path: "knowledge/orgs/#{SecureRandom.hex(4)}.md",
      content_hash: SecureRandom.hex(32),
      file_created_at: Time.current, file_updated_at: Time.current, indexed_at: Time.current
    )
  end

  test "start_timer! legt einen laufenden Eintrag an" do
    entry = TimeEntry.start_timer!(actor: @hans, topic: @topic, subject: @task, billable: true)
    assert_predicate entry, :running?
    assert_nil entry.ended_at
    assert entry.billable
    assert_equal @topic.id, entry.topic_id
  end

  test "start_timer! PAUSIERT einen bereits laufenden Timer (nicht stoppen)" do
    first = TimeEntry.start_timer!(actor: @hans)
    second = TimeEntry.start_timer!(actor: @hans)
    assert_predicate first.reload, :paused?, "der erste Timer muss pausiert sein"
    assert second.running?
    assert_equal 1, TimeEntry.running.for_actor(@hans).count
    assert_equal 2, TimeEntry.active.for_actor(@hans).count   # beide bleiben auf der Leiste
  end

  test "pause! und resume! schließen/öffnen Segmente; resume pausiert andere" do
    a = TimeEntry.start_timer!(actor: @hans)
    a.pause!
    assert_predicate a.reload, :paused?
    assert_equal 0, a.time_segments.open.count
    b = TimeEntry.start_timer!(actor: @hans)   # läuft
    a.resume!                                   # soll b pausieren
    assert_predicate a.reload, :running?
    assert_predicate b.reload, :paused?
    assert_equal 2, a.time_segments.count       # ursprüngliches + neues Segment
  end

  test "finish! beendet hart und schließt das offene Segment" do
    e = TimeEntry.start_timer!(actor: @hans)
    e.finish!
    assert_predicate e.reload, :finished?
    assert_not_nil e.ended_at
    assert_equal 0, e.time_segments.open.count
  end

  test "end_reason: manuelle Pause/anderer Timer/Stop werden unterschieden" do
    a = TimeEntry.start_timer!(actor: @hans)
    a.pause!
    assert_equal "paused", a.time_segments.order(:id).last.end_reason
    TimeEntry.start_timer!(actor: @hans)  # pausiert a? a ist schon paused; neuer pausiert nichts
    a.resume!                             # a läuft
    TimeEntry.start_timer!(actor: @hans)  # pausiert a wegen anderem Timer
    assert_equal "superseded", a.reload.time_segments.order(:id).last.end_reason
    a.resume!
    a.finish!
    assert_equal "finished", a.reload.time_segments.order(:id).last.end_reason
  end

  test "events liefert ein chronologisches Ereignis-Log" do
    e = TimeEntry.start_timer!(actor: @hans)
    e.pause!
    e.resume!
    e.finish!
    labels = e.events.map { |ev| ev[:label] }
    assert_equal ["Bearbeitung gestartet", "Bearbeitung pausiert",
                  "Bearbeitung fortgesetzt", "Bearbeitung beendet"], labels
  end

  test "ein zweiter manuell laufender Timer je Actor ist ungültig" do
    TimeEntry.start_timer!(actor: @hans)
    dup = TimeEntry.new(actor: @hans, started_at: Time.current)  # ended_at nil = laufend
    refute_predicate dup, :valid?
    assert dup.errors.added?(:base, "Es läuft bereits ein Timer für diesen Actor")
  end

  test "ein laufender Timer je Actor erlaubt parallele Timer verschiedener Actors" do
    me = create_agent
    TimeEntry.start_timer!(actor: @hans)
    other = TimeEntry.new(actor: me, started_at: Time.current)
    assert_predicate other, :valid?
  end

  test "duration_minutes summiert die Segmente (manueller Eintrag)" do
    t0 = Time.current
    entry = TimeEntry.log_manual!(actor: @hans, started_at: t0, minutes: 90)
    assert_predicate entry, :finished?
    assert_equal 90, entry.duration_minutes
    assert_equal 1, entry.time_segments.count
  end

  test "ended_at vor started_at ist ungültig" do
    t0 = Time.current
    entry = TimeEntry.new(actor: @hans, started_at: t0, ended_at: t0 - 5.minutes)
    refute_predicate entry, :valid?
    assert entry.errors.added?(:ended_at, "muss nach dem Start liegen")
  end

  test "Inhaltsbezug: Task wird über subject_id_int gesetzt und aufgelöst" do
    entry = TimeEntry.create!(actor: @hans, started_at: Time.current)
    entry.assign_subject(@task)
    entry.save!
    assert_equal "Task", entry.subject_type
    assert_equal @task.id, entry.subject_id_int
    assert_equal @task, entry.subject
  end

  test "Inhaltsbezug: KnowledgeItem wird über subject_uuid gesetzt und aufgelöst" do
    ki = person_ki
    entry = TimeEntry.create!(actor: @hans, started_at: Time.current)
    entry.assign_subject(ki)
    entry.save!
    assert_equal "KnowledgeItem", entry.subject_type
    assert_equal ki.uuid, entry.subject_uuid
    assert_equal ki, entry.subject
  end

  test "Topic wird mit Kunde zum Projekt" do
    kunde = person_ki("Mustermann AG")
    refute_predicate @topic, :project?
    @topic.update!(customer: kunde, billable: true)
    assert_predicate @topic.reload, :project?
    assert_equal kunde, @topic.customer
    assert_includes Topic.projects, @topic
  end

  # #762 (Hans, 2026-06-23): kind "address" gibt es nicht mehr (Adressen =
  # PostalAddress). Der billing-Scope auf ContactPoint bleibt; hier mit einem
  # gültigen Kind getestet.
  test "ContactPoint billing-Scope markiert den als billing markierten Kontaktpunkt" do
    kunde = person_ki
    marked   = kunde.contact_points.create!(kind: "email", value: "billing@example.com", billing: true)
    unmarked = kunde.contact_points.create!(kind: "email", value: "other@example.com")
    assert_includes kunde.contact_points.billing, marked
    refute_includes kunde.contact_points.billing, unmarked
  end
end
