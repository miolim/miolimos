require "test_helper"

# #573: Kalender — Misch-Blade, Schnell-Erfassung (Termin + Anruf), ICS-Feed.
class CalendarControllerTest < ActionDispatch::IntegrationTest
  setup do
    @hans = HumanActor.create!(name: "Hans", email: "hans-cal-#{SecureRandom.hex(3)}@t.local",
                               password: "secretsecret", role: :admin)
    grant(@hans, "Event", %w[read create update delete])
    grant(@hans, "Task", %w[read])
    grant(@hans, "Topic", %w[read])
    grant(@hans, "Communication", %w[read create update])
    grant(@hans, "KnowledgeItem", %w[read create])   # #598: Anruf legt Personen-Stub an
    post "/login", params: { email: @hans.email, password: "secretsecret" }
  end

  test "Kalender-Blade mischt Ereignisse, Meilensteine, Fälligkeiten und Wartepunkte" do
    monat = Date.new(2026, 7, 1)
    Event.create!(title: "Workshop Kickoff", starts_at: monat + 2.days + 10.hours, creator: @hans)
    ms = Task.create!(title: "MS-Abnahme", creator: @hans, status: :open,
                      client_milestone: true, due_date: monat + 10.days, skip_default_assignee: true)
    Task.create!(title: "Faellige-Aufgabe", creator: @hans, status: :open,
                 due_date: monat + 5.days, skip_default_assignee: true)
    Awaiting.create!(title: "Warte-auf-Angebot", creator: @hans, follow_up_at: monat + 7.days)

    get "/calendar/list_card", params: { month: "2026-07" }
    assert_response :success
    assert_includes @response.body, "Workshop Kickoff"
    assert_includes @response.body, "MS-Abnahme"
    assert_includes @response.body, "Faellige-Aufgabe"
    assert_includes @response.body, "Warte-auf-Angebot"
    assert_includes @response.body, "Juli 2026"
    # In-place-Monatswechsel (Stack bleibt): Frame + Nav-Links.
    assert_includes @response.body, "calendar_list_frame"
    assert_includes @response.body, "month=2026-08"
  end

  test "Termin anlegen (Schnell-Erfassung) ersetzt das Blade im Ziel-Monat" do
    post "/calendar/events", params: { event: { title: "Neuer Termin",
                                                starts_at: "2026-08-15T14:00" } },
         headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_response :success
    e = Event.order(:id).last
    assert_equal "Neuer Termin", e.title
    assert_match %r{<turbo-stream action="replace" target="stack_card_list:calendar"}, @response.body
    assert_includes @response.body, "August 2026"
  end

  test "Anruf dokumentieren: Call (Communication) + verknüpftes Event + Topic-Link" do
    topic = Topic.create!(name: "Anruf-Projekt", slug: "ap-#{SecureRandom.hex(3)}", creator: @hans)
    assert_difference -> { Call.count } => 1, -> { Event.count } => 1 do
      post "/calendar/calls", params: { wer: "Frau Mustermann", direction: "outbound",
                                        at: "2026-06-10T11:30", notiz: "Angebot besprochen",
                                        topic_id: topic.id },
           headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end
    call = Call.order(:id).last
    assert call.outbound?
    assert_equal "Anruf: Frau Mustermann", call.subject
    assert_equal [ topic.id ], call.topics.pluck(:id)
    ev = Event.order(:id).last
    assert_equal call.id, ev.communication_id
    assert_equal topic.id, ev.topic_id
  end

  # #765 (Hans, 2026-06-23): Dauer setzt Endzeit am Event + erzeugt eine
  # Zeitbuchung, die der Anrufdauer entspricht.
  test "Anruf mit Dauer setzt Event-Endzeit und bucht die Zeit" do
    topic = Topic.create!(name: "Zeit-Projekt", slug: "zp-#{SecureRandom.hex(3)}", creator: @hans)
    assert_difference -> { Call.count } => 1, -> { TimeEntry.count } => 1 do
      post "/calendar/calls", params: { wer: "Herr Beispiel", direction: "inbound",
                                        at: "2026-06-10T09:00", dauer: "25", topic_id: topic.id },
           headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end
    call = Call.order(:id).last
    assert_equal 25, call.duration_minutes
    ev = Event.order(:id).last
    assert_equal Time.zone.parse("2026-06-10T09:25"), ev.ends_at
    te = TimeEntry.order(:id).last
    assert_equal "Communication", te.subject_type
    assert_equal call.id, te.subject_id_int
    assert_equal topic.id, te.topic_id
    assert_equal 25, te.duration_minutes
  end

  test "Anruf ohne Dauer erzeugt KEINE Zeitbuchung und keine Endzeit" do
    assert_no_difference -> { TimeEntry.count } do
      post "/calendar/calls", params: { wer: "Ohne Dauer", at: "2026-06-10T09:00" },
           headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end
    assert_nil Event.order(:id).last.ends_at
    assert_nil Call.order(:id).last.duration_minutes
  end

  # #765 (Hans, 2026-06-23): Dauer nachträglich setzen/ändern aktualisiert
  # Event-Endzeit und Zeitbuchung; auf 0 setzen entfernt beide wieder.
  test "Anrufdauer nachträglich setzen, ändern und entfernen" do
    post "/calendar/calls", params: { wer: "Nachträglich", at: "2026-06-10T09:00" },
         headers: { "Accept" => "text/vnd.turbo-stream.html" }
    call = Call.order(:id).last

    # Setzen: 30 Min → Endzeit + neue Zeitbuchung
    assert_difference -> { TimeEntry.count } => 1 do
      patch "/communications/#{call.id}/call_duration", params: { duration_minutes: "30" }
    end
    assert_equal 30, call.reload.duration_minutes
    assert_equal Time.zone.parse("2026-06-10T09:30"), call.event.reload.ends_at
    assert_equal 30, TimeEntry.for_subject(call).first.duration_minutes

    # Ändern: 45 Min → keine NEUE Buchung, vorhandene angepasst
    assert_no_difference -> { TimeEntry.count } do
      patch "/communications/#{call.id}/call_duration", params: { duration_minutes: "45" }
    end
    assert_equal 45, call.reload.duration_minutes
    assert_equal Time.zone.parse("2026-06-10T09:45"), call.event.reload.ends_at
    assert_equal 45, TimeEntry.for_subject(call).first.duration_minutes

    # Entfernen: 0 → Buchung + Endzeit weg
    assert_difference -> { TimeEntry.count } => -1 do
      patch "/communications/#{call.id}/call_duration", params: { duration_minutes: "0" }
    end
    assert_nil call.reload.duration_minutes
    assert_nil call.event.reload.ends_at
  end

  test "ICS-Feed: gültiger Token liefert VCALENDAR mit Events + Meilensteinen, ohne 403" do
    Event.create!(title: "ICS-Termin", starts_at: 1.week.from_now, creator: @hans)
    Task.create!(title: "ICS-Meilenstein", creator: @hans, status: :open,
                 client_milestone: true, due_date: 2.weeks.from_now.to_date,
                 skip_default_assignee: true)

    delete "/logout"   # Feed braucht KEINE Session — nur den Token
    get "/calendar/feed", params: { token: CalendarController.feed_token(@hans) }  # #602 S2: Token je Nutzer
    assert_response :success
    assert_equal "text/calendar", @response.media_type
    assert_includes @response.body, "BEGIN:VCALENDAR"
    assert_includes @response.body, "ICS-Termin"
    assert_includes @response.body, "Meilenstein: ICS-Meilenstein"

    get "/calendar/feed", params: { token: "manipuliert" }
    assert_response :forbidden
  end

  test "Portal: freigegebener Termin erscheint auf der Termine-Seite, ungeteilter nicht" do
    topic  = Topic.create!(name: "Portal-Cal", slug: "pc-#{SecureRandom.hex(3)}", creator: @hans)
    access = PortalAccess.create!(topic: topic, email: "cal-kunde@example.com")
    Event.create!(title: "Geteilter Workshop", starts_at: 1.week.from_now,
                  topic: topic, portal_visible: true, creator: @hans)
    Event.create!(title: "Interner Termin", starts_at: 1.week.from_now,
                  topic: topic, creator: @hans)

    get "/portal/session/#{access.magic_token}"
    get "/portal/termine"
    assert_response :success
    assert_includes @response.body, "Geteilter Workshop"
    refute_includes @response.body, "Interner Termin"
  end
  test "/calendar rendert die Stack-Seite mit dem Kalender-Blade" do
    get "/calendar"
    assert_response :success
    assert_includes @response.body, "stack_card_list:calendar"
    assert_includes @response.body, "blade-stack"
  end
  # ── #573 v2 ────────────────────────────────────────────────────────────────
  test "Termin bearbeiten und löschen (Inline-Form)" do
    e = Event.create!(title: "Alt", starts_at: Time.zone.parse("2026-09-01 10:00"), creator: @hans)

    patch "/calendar/events/#{e.id}", params: { event: { title: "Neu", starts_at: "2026-09-02T11:00" } },
          headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_response :success
    e.reload
    assert_equal "Neu", e.title
    assert_equal 2, e.starts_at.day

    delete "/calendar/events/#{e.id}", headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_response :success
    refute Event.exists?(e.id)
    assert_includes @response.body, "gelöscht"
  end

  # #598: Tagesansicht (Reihenfolge Tag|Woche|Monat) + Personen-Verknüpfung.
  test "Tagesansicht: view=day zeigt nur den einen Tag" do
    Event.create!(title: "Tages-Termin", starts_at: Date.new(2026, 7, 8).to_time + 9.hours, creator: @hans)
    Event.create!(title: "Anderer-Tag", starts_at: Date.new(2026, 7, 9).to_time + 9.hours, creator: @hans)
    get "/calendar/list_card", params: { month: "2026-07-08", view: "day" }
    assert_response :success
    assert_includes @response.body, "Tages-Termin"
    refute_includes @response.body, "Anderer-Tag"
    assert_includes @response.body, "month=2026-07-09"   # Tages-Nav springt um 1 Tag
    assert_match %r{>Tag</a>.*>Woche</a>.*>Monat</a>}m, @response.body
  end

  test "Anruf dokumentieren verknüpft die Person als KI (bestehend oder Stub)" do
    assert_difference -> { KnowledgeItem.where(item_type: "person").count }, 1 do
      post "/calendar/calls", params: { wer: "Erika Beispiel", direction: "inbound",
                                        at: "2026-06-11T09:00" },
           headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end
    call = Call.order(:id).last
    person = KnowledgeItem.by_title_ci("Erika Beispiel").first
    assert_equal [person.uuid], call.communication_mentions.pluck(:mentioned_uuid)

    # zweiter Anruf mit gleicher Person: kein zweiter Stub
    assert_no_difference -> { KnowledgeItem.where(item_type: "person").count } do
      post "/calendar/calls", params: { wer: "erika beispiel", direction: "outbound",
                                        at: "2026-06-11T10:00" },
           headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end
  end

  test "Wochenansicht: view=week zeigt KW-Label und Tagesliste" do
    Event.create!(title: "Wochen-Termin", starts_at: Date.new(2026, 7, 8).to_time + 9.hours, creator: @hans)
    get "/calendar/list_card", params: { month: "2026-07-08", view: "week" }
    assert_response :success
    assert_includes @response.body, "KW 28"
    assert_includes @response.body, "Wochen-Termin"
    # Wochen-Nav springt um 7 Tage
    assert_includes @response.body, "month=2026-07-15"
    assert_includes @response.body, "view=week"
  end

  test "Topic-Kalender-Reiter: nur Zeitobjekte des Topics, in-place-Frame" do
    # #789-Begleitfix: Zeit auf Monatsmitte einfrieren. Der Test legt ein
    # Event auf Time.current + 1.day und erwartet es im aktuellen Monats-
    # kalender; am Monatsletzten (z.B. 30.6.) fiel „morgen" in den Folgemonat
    # und das Event war nicht im gerenderten Monat → Fehlschlag. travel_to
    # wird von Rails nach dem Test automatisch zurückgesetzt.
    travel_to Time.zone.local(2026, 6, 15, 12, 0)
    grant(@hans, "Awaiting", %w[read])
    topic = Topic.create!(name: "Cal-Topic", slug: "ct-#{SecureRandom.hex(3)}", creator: @hans)
    fremd = Topic.create!(name: "Fremd-Topic", slug: "ft-#{SecureRandom.hex(3)}", creator: @hans)
    Event.create!(title: "Topic-Termin", starts_at: Time.current + 1.day, topic: topic, creator: @hans)
    Event.create!(title: "Fremd-Termin", starts_at: Time.current + 1.day, topic: fremd, creator: @hans)

    get "/topics/#{topic.slug}/calendar_tab"
    assert_response :success
    assert_includes @response.body, "topic_calendar_frame_#{topic.id}"
    assert_includes @response.body, "Topic-Termin"
    refute_includes @response.body, "Fremd-Termin"

    # Reiter erscheint im Topic-Blade
    get "/topics/#{topic.slug}/list_card", params: { tab: "kalender" }
    assert_response :success
    assert_includes @response.body, "Topic-Termin"
  end

  test "GcalPush: ohne Calendar-Scope stiller No-Op, Event funktioniert normal" do
    refute GcalPush.enabled?
    e = Event.create!(title: "Ohne-Push", starts_at: Time.current + 1.day, creator: @hans)
    assert_nil e.reload.gcal_event_id
  end
end
