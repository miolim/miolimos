require "test_helper"

# #533 Phase 1b (Hans, 2026-06-07): Zeitbuchungs-Engine (start/stop/manual/running).
class TimeEntriesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @hans = HumanActor.create!(
      name: "Hans", email: "hans-te-#{SecureRandom.hex(3)}@t.local", password: "secretsecret"
    )
    grant(@hans, "Task", %w[read create update])
    @topic = Topic.create!(name: "Projekt X", slug: "projekt-x-#{SecureRandom.hex(3)}", creator: @hans)
    @task  = Task.create!(title: "Etwas tun", creator: @hans)
    post "/login", params: { email: @hans.email, password: "secretsecret" }
  end

  def json = JSON.parse(@response.body)

  test "create startet einen Timer mit Projekt und Aufgabenbezug" do
    post "/time_entries", params: {
      mode: "timer", topic_id: @topic.id, subject_type: "Task", subject_id: @task.id,
      note: "Anfang", billable: "1"
    }, headers: { "Accept" => "application/json" }
    assert_response :success
    assert_equal true, json["running"]
    assert_equal @topic.id, json.dig("entry", "topic", "id")
    assert_equal "Etwas tun", json.dig("entry", "subject", "label")
    assert_equal 1, TimeEntry.running.for_actor(@hans).count
  end

  test "ein zweiter Start stoppt den vorigen Timer (Ein-Timer-Regel)" do
    post "/time_entries", params: { mode: "timer", topic_id: @topic.id }, headers: { "Accept" => "application/json" }
    post "/time_entries", params: { mode: "timer", topic_id: @topic.id }, headers: { "Accept" => "application/json" }
    assert_response :success
    assert_equal 1, TimeEntry.running.for_actor(@hans).count
    assert_equal 2, TimeEntry.for_actor(@hans).count
  end

  test "stop beendet den laufenden Timer" do
    post "/time_entries", params: { mode: "timer", topic_id: @topic.id }, headers: { "Accept" => "application/json" }
    post "/time_entries/stop", headers: { "Accept" => "application/json" }
    assert_response :success
    assert_equal false, json["running"]
    assert_equal 0, TimeEntry.running.for_actor(@hans).count
  end

  test "running spiegelt den aktuellen Zustand" do
    get "/time_entries/running", headers: { "Accept" => "application/json" }
    assert_equal false, json["running"]
    post "/time_entries", params: { mode: "timer", topic_id: @topic.id }, headers: { "Accept" => "application/json" }
    get "/time_entries/running", headers: { "Accept" => "application/json" }
    assert_equal true, json["running"]
  end

  test "manueller Eintrag erzeugt eine fertige Buchung mit Dauer, kein laufender Timer" do
    start = "2026-06-01T09:00:00"
    post "/time_entries", params: {
      mode: "manual", topic_id: @topic.id, started_at: start, minutes: 45, note: "Nachtrag"
    }, headers: { "Accept" => "application/json" }
    assert_response :success
    assert_equal false, json["running"]
    entry = TimeEntry.for_actor(@hans).order(:id).last
    assert_not_nil entry.ended_at
    assert_equal 45, entry.duration_minutes
  end

  # #533 #2b/#3/#4: Detail-Blade + Bearbeiten.
  test "card rendert das Detail-Blade mit Ereignis-Log" do
    e = TimeEntry.start_timer!(actor: @hans, topic: @topic, subject: @task)
    e.pause!
    get card_time_entry_path(e), headers: { "Accept" => "text/html" }
    assert_response :success
    assert_includes @response.body, "Zeitbuchung"
    assert_includes @response.body, "Bearbeitung gestartet"
  end

  test "update_times: nur Dauer setzt ein Segment dieser Länge" do
    e = TimeEntry.log_manual!(actor: @hans, started_at: Time.current, minutes: 10, topic: @topic, subject: @task)
    patch update_times_time_entry_path(e), params: { minutes: 25 }, headers: { "Accept" => "application/json" }
    assert_response :success
    assert_equal 25, e.reload.duration_minutes
  end

  test "destroy löscht die Buchung samt Segmenten" do
    e = TimeEntry.log_manual!(actor: @hans, started_at: Time.current, minutes: 10)
    assert_difference -> { TimeEntry.count }, -1 do
      delete time_entry_path(e), headers: { "Accept" => "application/json" }
    end
    assert_response :success
  end

  # #533 1d: globale Zeiten-Liste.
  test "index rendert die Zeiten-Übersicht" do
    TimeEntry.log_manual!(actor: @hans, started_at: Time.current, minutes: 30, topic: @topic, subject: @task)
    get "/time_entries"
    assert_response :success
    assert_includes @response.body, "Zeiten"
    assert_includes @response.body, "Summe"
  end

  # #557: Standalone-Card des Zeiten-Blades (für Sidebar-Append + Restore).
  test "list_card rendert das Zeiten-Blade als Fragment" do
    TimeEntry.log_manual!(actor: @hans, started_at: Time.current, minutes: 30, topic: @topic, subject: @task)
    get "/time_entries/list_card"
    assert_response :success
    assert_includes @response.body, "stack_card_list:time_entries"
  end

  # #541: billable nachträglich umschalten (das fehlende Interface).
  test "set_billable markiert eine Buchung als abrechenbar und zurück" do
    e = TimeEntry.log_manual!(actor: @hans, started_at: Time.current, minutes: 30, topic: @topic)
    refute e.billable?
    patch "/time_entries/#{e.id}/set_billable", params: { billable: "1" }
    assert e.reload.billable?
    patch "/time_entries/#{e.id}/set_billable", params: { billable: "0" }
    refute e.reload.billable?
  end

  test "index Reiter nach Aufgabe konsolidiert" do
    TimeEntry.log_manual!(actor: @hans, started_at: Time.current, minutes: 30, topic: @topic, subject: @task)
    get "/time_entries", params: { tab: "task" }
    assert_response :success
    assert_includes @response.body, @task.title
  end

  test "index Reiter nach Topic konsolidiert" do
    TimeEntry.log_manual!(actor: @hans, started_at: Time.current, minutes: 30, topic: @topic, subject: @task)
    get "/time_entries", params: { tab: "topic" }
    assert_response :success
    assert_includes @response.body, @topic.name
  end

  # #533 #2: Pause/Fortsetzen je einzelnem Timer.
  test "pause pausiert einen Timer, resume setzt ihn fort" do
    post "/time_entries", params: { mode: "timer", topic_id: @topic.id }, headers: { "Accept" => "application/json" }
    id = json.dig("entry", "id")
    post "/time_entries/#{id}/pause", headers: { "Accept" => "application/json" }
    assert_response :success
    assert_equal false, json["running"]
    assert_equal 1, TimeEntry.active.for_actor(@hans).count   # bleibt auf der Leiste
    post "/time_entries/#{id}/resume", headers: { "Accept" => "application/json" }
    assert_equal true, json["running"]
  end

  # #588 v2 (Hans, 2026-06-12): Fokus-Verlust schließt die Strecke als
  # EIGENE Zeitbuchung ab (Start→Ende = Dauer); Refokus startet eine NEUE.
  # Mini-Strecken unter 30s werden verworfen.
  test "reply_pause finisht die Strecke als eigene Buchung, Refokus startet neue" do
    post "/time_entries/reply_start",
         params: { subject_type: "Task", subject_id: @task.id },
         headers: { "Accept" => "application/json" }
    entry = TimeEntry.running.for_actor(@hans).first
    refute_nil entry
    # Strecke künstlich ≥30s machen, damit sie behalten wird.
    entry.time_segments.first.update!(started_at: 2.minutes.ago)
    entry.update!(started_at: 2.minutes.ago)

    post "/time_entries/reply_pause",
         params: { subject_type: "Task", subject_id: @task.id },
         headers: { "Accept" => "application/json" }
    assert_response :success
    entry.reload
    assert entry.finished?, "Strecke wird als eigene Buchung abgeschlossen"
    refute_nil entry.ended_at
    assert_in_delta 120, (entry.ended_at - entry.started_at), 10
    assert_equal false, json["running"]

    # Refokus → NEUE Buchung (die alte bleibt finished bestehen).
    post "/time_entries/reply_start",
         params: { subject_type: "Task", subject_id: @task.id },
         headers: { "Accept" => "application/json" }
    fresh = TimeEntry.running.for_actor(@hans).first
    refute_nil fresh
    refute_equal entry.id, fresh.id, "Refokus startet einen neuen Eintrag"

    # Mini-Strecke (<30s): sofortiges reply_pause verwirft den Eintrag.
    post "/time_entries/reply_pause",
         params: { subject_type: "Task", subject_id: @task.id },
         headers: { "Accept" => "application/json" }
    assert_response :success
    refute TimeEntry.exists?(fresh.id), "Mini-Strecke wird verworfen"

    # reply_pause ohne laufenden Timer ist ein No-Op (kein 500)
    post "/time_entries/reply_pause",
         params: { subject_type: "Task", subject_id: @task.id },
         headers: { "Accept" => "application/json" }
    assert_response :success
  end

  test "ein neuer Timer pausiert den laufenden, beide bleiben aktiv" do
    post "/time_entries", params: { mode: "timer", topic_id: @topic.id }, headers: { "Accept" => "application/json" }
    post "/time_entries", params: { mode: "timer", topic_id: @topic.id }, headers: { "Accept" => "application/json" }
    assert_equal 1, TimeEntry.running.for_actor(@hans).count
    assert_equal 2, TimeEntry.active.for_actor(@hans).count
    assert_equal 2, json["active"].length
  end

  # #533 #1: Auto-Timer beim Antwort-Bearbeiten.
  test "reply_start startet einen Timer für die Aufgabe (Projekt aus einzigem Thema)" do
    @task.task_topics.create!(topic: @topic)
    post "/time_entries/reply_start", params: { subject_type: "Task", subject_id: @task.id },
         headers: { "Accept" => "application/json" }
    assert_response :success
    entry = TimeEntry.for_actor(@hans).last
    assert_predicate entry, :running?
    assert_equal "Task", entry.subject_type
    assert_equal @task.id, entry.subject_id_int
    assert_equal @topic.id, entry.topic_id
  end

  test "reply_start startet keinen zweiten Timer, wenn schon einer für die Aufgabe läuft" do
    post "/time_entries/reply_start", params: { subject_type: "Task", subject_id: @task.id }, headers: { "Accept" => "application/json" }
    assert_difference -> { TimeEntry.count }, 0 do
      post "/time_entries/reply_start", params: { subject_type: "Task", subject_id: @task.id }, headers: { "Accept" => "application/json" }
    end
  end

  test "reply_start setzt einen pausierten Aufgaben-Timer nur fort (kein neuer)" do
    post "/time_entries/reply_start", params: { subject_type: "Task", subject_id: @task.id }, headers: { "Accept" => "application/json" }
    task_entry = TimeEntry.for_actor(@hans).last
    # anderer Timer -> pausiert den Aufgaben-Timer
    post "/time_entries", params: { mode: "timer", topic_id: @topic.id }, headers: { "Accept" => "application/json" }
    assert_predicate task_entry.reload, :paused?
    assert_difference -> { TimeEntry.count }, 0 do
      post "/time_entries/reply_start", params: { subject_type: "Task", subject_id: @task.id }, headers: { "Accept" => "application/json" }
    end
    assert_predicate task_entry.reload, :running?
  end

  test "reply_end beendet den Timer der Aufgabe hart" do
    post "/time_entries/reply_start", params: { subject_type: "Task", subject_id: @task.id }, headers: { "Accept" => "application/json" }
    post "/time_entries/reply_end", params: { subject_type: "Task", subject_id: @task.id }, headers: { "Accept" => "application/json" }
    assert_response :success
    assert_predicate TimeEntry.for_actor(@hans).last, :finished?
  end

  # #533 1c: Beim Start von einer Aufgabe ohne Topic wird das gewählte
  # Projekt der Aufgabe mit verknüpft (link_topic).
  test "link_topic verknüpft das Projekt mit der bisher topiclosen Aufgabe" do
    assert_empty @task.topics
    post "/time_entries", params: {
      mode: "timer", topic_id: @topic.id, subject_type: "Task", subject_id: @task.id, link_topic: "1"
    }, headers: { "Accept" => "application/json" }
    assert_response :success
    assert_includes @task.reload.topics, @topic
  end

  # replace_topics stellt Gleichlauf her: nur das gewählte Projekt bleibt.
  test "replace_topics entfernt andere Projekte der Aufgabe" do
    other = Topic.create!(name: "Alt", slug: "alt-#{SecureRandom.hex(3)}", creator: @hans)
    @task.task_topics.create!(topic: other)
    post "/time_entries", params: {
      mode: "timer", topic_id: @topic.id, subject_type: "Task", subject_id: @task.id, replace_topics: "1"
    }, headers: { "Accept" => "application/json" }
    assert_response :success
    assert_equal [@topic.id], @task.reload.topics.pluck(:id)
  end

  # #770 (Hans): KI-Timetracking lief faktisch nicht — das Editieren des
  # KI-Bodys startete keinen Auto-Timer (das View-Formular trug die
  # reply-timer-Verdrahtung nicht). Der Backend-Pfad muss eine KI als Subjekt
  # tragen (subject_uuid), damit das nachgezogene Formular auch greift.
  test "reply_start startet einen Timer für ein Wissens-Item (subject_uuid)" do
    grant(@hans, "KnowledgeItem", %w[read create update])
    ki = FileProxy.create(actor: @hans, title: "Langer Body", item_type: :note,
                          content: "x" * 500, topics: [], contacts: [], tags: [])
    assert_difference -> { TimeEntry.where(subject_type: "KnowledgeItem", subject_uuid: ki.uuid).count }, 1 do
      post "/time_entries/reply_start",
           params: { subject_type: "KnowledgeItem", subject_id: ki.uuid },
           headers: { "Accept" => "application/json" }
    end
    assert_response :success
    entry = TimeEntry.find_by(subject_type: "KnowledgeItem", subject_uuid: ki.uuid)
    assert entry.running?
    assert_equal @hans.id, entry.actor_id
  end
end
