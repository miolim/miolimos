require "test_helper"

# #203: Coverage fuer den User-Verlauf (#160). #631: /history ist jetzt
# eine Blade-Stack-Seite — Einstieg ist das Verlauf-Listen-Blade.
class HistoryControllerTest < ActionDispatch::IntegrationTest
  setup do
    @hans = HumanActor.create!(name: "Hans",
                                email: "hans-hist-#{SecureRandom.hex(3)}@t.local",
                                password: "secretsecret")
    grant(@hans, "Actor",         %w[read])
    grant(@hans, "KnowledgeItem", %w[read create update delete])
    grant(@hans, "Task",          %w[read create update delete])
    post "/login", params: { email: @hans.email, password: "secretsecret" }
  end

  test "GET /history rendert das Verlauf-Listen-Blade (#631)" do
    get "/history"
    assert_response :success
    assert_includes @response.body, %q(data-uuid="list:history")
  end

  test "Verlauf listet zuletzt angeschaute KIs, Tasks und Sources" do
    ki   = FileProxy.create(actor: @hans, title: "Notiz A", item_type: :note, content: "x")
    task = Task.create!(title: "Task A", creator: @hans, assignee: @hans)
    src  = Source.create!(slug: "src-a", title: "Quelle A", csl_type: "book", creator: @hans)
    ActorView.create!(actor: @hans, viewable_type: "KnowledgeItem", viewable_id: ki.uuid,
                       viewed_at: 3.minutes.ago)
    ActorView.create!(actor: @hans, viewable_type: "Task",          viewable_id: task.id.to_s,
                       viewed_at: 2.minutes.ago)
    ActorView.create!(actor: @hans, viewable_type: "Source",        viewable_id: src.id.to_s,
                       viewed_at: 1.minute.ago)

    get "/history"
    assert_response :success
    assert_select "a", text: "Notiz A"
    assert_select "a", text: "Task A"
    assert_select "a", text: "Quelle A"
  end

  test "DISTINCT ON dedupt mehrfach-angeschaute Entity auf juengsten View" do
    ki = FileProxy.create(actor: @hans, title: "Mehrfach besucht", item_type: :note, content: "x")
    ActorView.create!(actor: @hans, viewable_type: "KnowledgeItem", viewable_id: ki.uuid,
                       viewed_at: 1.hour.ago, was_edited: false)
    ActorView.create!(actor: @hans, viewable_type: "KnowledgeItem", viewable_id: ki.uuid,
                       viewed_at: 5.minutes.ago, was_edited: true)

    get "/history"
    assert_response :success
    assert_equal 1, css_select("a:contains('Mehrfach besucht')").size
  end

  test "stack-restore rendert Liste + Entitaets-Blade serverseitig (#631)" do
    task = Task.create!(title: "Restore-Task", creator: @hans, assignee: @hans)
    get "/history", params: { stack: "list:history,task:#{task.id}" }
    assert_response :success
    assert_includes @response.body, %q(data-uuid="list:history")
    assert_includes @response.body, %Q(data-uuid="task:#{task.id}")
  end

  # #632: Personen-KIs als eigener Filter-Typ.
  test "Personen-KI bekommt data-type=Person, Notiz bleibt KnowledgeItem" do
    note   = FileProxy.create(actor: @hans, title: "Filter-Notiz", item_type: :note, content: "x")
    person = FileProxy.create(actor: @hans, title: "Max Filtermann", item_type: :person, content: "x")
    ActorView.create!(actor: @hans, viewable_type: "KnowledgeItem", viewable_id: note.uuid,
                       viewed_at: 2.minutes.ago)
    ActorView.create!(actor: @hans, viewable_type: "KnowledgeItem", viewable_id: person.uuid,
                       viewed_at: 1.minute.ago)

    get "/history"
    assert_response :success
    assert_select "li[data-type='Person'] a", text: "Max Filtermann"
    assert_select "li[data-type='KnowledgeItem'] a", text: "Filter-Notiz"
    assert_select "button[data-type='Person']", text: /Personen/
  end

  # #631 v2: „Mehr laden"-Endpoint blättert über before-Timestamp.
  test "history#more liefert ältere Zeilen im passenden Frame" do
    old_ki = FileProxy.create(actor: @hans, title: "Uralt-Notiz", item_type: :note, content: "x")
    new_ki = FileProxy.create(actor: @hans, title: "Frisch-Notiz", item_type: :note, content: "x")
    ActorView.create!(actor: @hans, viewable_type: "KnowledgeItem", viewable_id: old_ki.uuid,
                       viewed_at: 3.days.ago)
    ActorView.create!(actor: @hans, viewable_type: "KnowledgeItem", viewable_id: new_ki.uuid,
                       viewed_at: 5.minutes.ago)

    before = 1.day.ago.to_f.to_s
    get "/history/more", params: { before: before }
    assert_response :success
    assert_includes @response.body, "history_more_#{before.tr('.', '-')}"
    assert_includes @response.body, "Uralt-Notiz"
    refute_includes @response.body, "Frisch-Notiz"

    # Nichts mehr übrig → Ende-Marker.
    get "/history/more", params: { before: 10.days.ago.to_f.to_s }
    assert_includes @response.body, "Ende des Verlaufs."
  end

  test "list_card liefert die Listen-Card (Restore-Fetch)" do
    get "/history/list_card"
    assert_response :success
    assert_includes @response.body, %q(data-uuid="list:history")
  end
end
