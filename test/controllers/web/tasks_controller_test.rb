require "test_helper"

class TasksControllerTest < ActionDispatch::IntegrationTest
  setup do
    @hans = HumanActor.create!(
      name: "Hans", email: "hans-tasks-#{SecureRandom.hex(3)}@t.local",
      password: "secretsecret"
    )
    grant(@hans, "Task", %w[read create update delete])
    grant(@hans, "Topic", %w[read update])
    grant(@hans, "Contact", %w[read])
    grant(@hans, "KnowledgeItem", %w[read])
    grant(@hans, "Communication", %w[read])

    post "/login", params: { email: @hans.email, password: "secretsecret" }
  end

  # #739 (Hans): Quick-Anlage ohne Titel darf nicht an der Titel-Validierung
  # scheitern (vorher render :new = Sprung aus dem Stack). Stattdessen mit
  # Platzhalter anlegen, an den Stack appenden, Cursor ins Titelfeld.
  test "POST /tasks ohne Titel legt Platzhalter-Aufgabe an und fokussiert Titelfeld" do
    assert_difference -> { Task.count }, 1 do
      post "/tasks", params: { title: "" },
           headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end
    assert_response :ok
    task = Task.order(:created_at).last
    assert_equal "Neue Aufgabe", task.title
    # Die frisch angehängte Blade-Card fokussiert das Titelfeld (nicht das
    # Beschreibungsfeld), damit man direkt den echten Titel tippt.
    assert_includes @response.body, 'data-focus-after-add="title"'
    refute_includes @response.body, 'data-focus-after-add="description"'
  end

  # #458 (Hans, 2026-06-02): Im Details-Heading stehen die konkreten Themen
  # mit Farbmarkierer statt der Anzahl.
  test "Details-Heading zeigt Themen mit Marker statt Anzahl" do
    topic = Topic.create!(name: "MarkerThema-XZ", slug: "marker-#{SecureRandom.hex(3)}",
                          color: "#ff0000", creator: @hans)
    task = Task.create!(title: "Themen-Heading-Probe", creator: @hans, status: :open)
    task.topics << topic
    get "/tasks/#{task.id}/card"
    assert_response :success
    assert_includes @response.body, 'data-task-pickers-summary-target="topics"'
    assert_includes @response.body, "MarkerThema-XZ"
    refute_match %r{·\s*1\s*Thema(\b|<)}, @response.body
  end

  # #451 (Hans, 2026-06-02): Der Veröffentlichen-Button im Entwurfs-Task-
  # Blade traegt data-task-publish, damit Strg+Umschalt+Enter ihn robust
  # findet und klickt (Aufgabe veroeffentlichen).
  test "Entwurfs-Task-Blade: Publish-Button traegt data-task-publish" do
    agent = AgentActor.create!(name: "Bauer", description: "Build-Agent",
                               email: "bauer-#{SecureRandom.hex(3)}@miolim.de")
    task = Task.create!(title: "Agenten-Entwurf", description: "tu was",
                        creator: @hans, assignee: agent, status: :open)
    assert task.draft?
    get "/tasks/#{task.id}/card"
    assert_response :success
    assert_includes @response.body, "data-task-publish"
    assert_match %r{action="[^"]*/tasks/#{task.id}/publish"}, @response.body
  end

  test "GET /tasks blendet Tasks aus Template-Topics aus" do
    template = Topic.create!(name: "Vorlage X", slug: "vorlage-x-#{SecureRandom.hex(2)}",
                             creator: @hans, template: true)
    regular  = Topic.create!(name: "Regulär X", slug: "regulaer-x-#{SecureRandom.hex(2)}",
                             creator: @hans)
    template_task = Task.create!(title: "Vorlage-Aufgabe-XYZ", creator: @hans, assignee: @hans)
    TaskTopic.create!(task: template_task, topic: template)
    regular_task = Task.create!(title: "Echte-Aufgabe-XYZ", creator: @hans, assignee: @hans)
    TaskTopic.create!(task: regular_task, topic: regular)

    get "/tasks"
    assert_response :success
    assert_includes @response.body, "Echte-Aufgabe-XYZ"
    refute_includes @response.body, "Vorlage-Aufgabe-XYZ"
  end

  test "GET /tasks lists my assigned open tasks" do
    mine = Task.create!(title: "Mein Ding", creator: @hans, assignee: @hans, status: :open)
    get "/tasks"
    assert_response :success
    assert_includes @response.body, "Mein Ding"
  end

  test "POST /tasks defaults assignee to the current actor" do
    post "/tasks", params: { title: "Ohne Zuweisung" }
    task = Task.order(:id).last
    assert_equal @hans.id, task.assignee_id
  end

  test "POST /tasks quick-add with topic_id links via task_topics" do
    topic = Topic.create!(name: "T", slug: "t-#{SecureRandom.hex(3)}", creator: @hans)

    assert_difference -> { Task.count }, 1 do
      assert_difference -> { TaskTopic.count }, 1 do
        post "/tasks", params: { title: "Schnell-Aufgabe", topic_id: topic.id }
      end
    end
    task = Task.order(:id).last
    assert_equal "Schnell-Aufgabe", task.title
    assert_equal @hans.id, task.creator_id
    assert_includes task.topics, topic
  end

  test "POST /tasks nested task_topics requires Task update capability" do
    task = Task.create!(title: "x", creator: @hans)
    topic = Topic.create!(name: "T", slug: "t-#{SecureRandom.hex(3)}", creator: @hans)

    post "/tasks/#{task.id}/topics", params: { topic_id: topic.id }
    # expected: redirect back (fallback) or 200 — not a 403 because Hans has Task update
    refute_equal 403, response.status
    assert TaskTopic.exists?(task: task, topic: topic)
  end

  test "PATCH /tasks/:id updates status" do
    task = Task.create!(title: "t", creator: @hans)
    patch "/tasks/#{task.id}", params: { task: { status: "done" } }
    assert_redirected_to task_path(task)
    assert task.reload.done?
  end

  test "DELETE /tasks/:id soft-deletes (deleted_at set, row hidden by default scope)" do
    task = Task.create!(title: "t", creator: @hans)
    delete "/tasks/#{task.id}"
    assert_redirected_to tasks_path
    refute Task.exists?(task.id)            # default-scope blendet aus
    assert Task.with_discarded.exists?(task.id)  # aber noch da
    assert task.reload.discarded?
  end

  test "POST /tasks/:id/restore reverses soft-delete" do
    task = Task.create!(title: "t", creator: @hans)
    task.discard!
    post "/tasks/#{task.id}/restore",
         headers: { "Accept" => "text/vnd.turbo-stream.html" }
    refute task.reload.discarded?
  end

  test "GET /tasks/trash lists discarded tasks" do
    Task.create!(title: "lebt", creator: @hans, assignee: @hans)
    discarded = Task.create!(title: "trashed-x123", creator: @hans, assignee: @hans)
    discarded.discard!
    get "/tasks/trash"
    assert_response :success
    assert_includes @response.body, "trashed-x123"
    refute_includes @response.body, "lebt"
  end

  test "DELETE /tasks/:id succeeds even when task has audit logs" do
    task = Task.create!(title: "t", creator: @hans)
    # toggle_done erzeugt einen AuditLog (via Current.actor)
    post "/tasks/#{task.id}/toggle_done"
    assert task.reload.done?
    assert task.audit_logs.any?

    delete "/tasks/#{task.id}"
    assert_redirected_to tasks_path
    refute Task.exists?(task.id)
  end

  test "PATCH /tasks/:id with parent_id nests existing task as subtask" do
    parent = Task.create!(title: "parent", creator: @hans)
    child  = Task.create!(title: "floater", creator: @hans)

    patch "/tasks/#{child.id}", params: { task: { parent_id: parent.id } }
    assert_equal parent.id, child.reload.parent_id
    assert_includes parent.subtasks, child
  end

  test "parent_id cycle is rejected by validation" do
    a = Task.create!(title: "a", creator: @hans)
    b = Task.create!(title: "b", creator: @hans, parent: a)
    a.parent = b
    refute_predicate a, :valid?
    assert a.errors[:parent_id].any?
  end

  test "POST /tasks with parent_id creates subtask and redirects to parent" do
    parent = Task.create!(title: "parent", creator: @hans)
    assert_difference -> { parent.subtasks.count }, 1 do
      post "/tasks", params: { task: { title: "sub", parent_id: parent.id, status: "open" } }
    end
    sub = parent.subtasks.first
    assert_equal "sub", sub.title
  end

  test "PATCH /tasks/:id syncs contacts by slugs" do
    task = Task.create!(title: "t", creator: @hans)
    grant(@hans, "KnowledgeItem", %w[read create update delete])

    with_isolated_miolimos_base do
      slug = "alice-resolver-#{SecureRandom.hex(3)}"
      patch "/tasks/#{task.id}", params: { task: { contacts: slug } }

      expected_title = slug.split("-").map(&:capitalize).join(" ")
      alice = KnowledgeItem.persons.find_by(title: expected_title)
      assert_not_nil alice, "PersonKiResolver should have created Person-KI for #{slug}"
      assert_includes task.reload.mentioned_kis, alice

      patch "/tasks/#{task.id}", params: { task: { contacts: "" } }
      assert_empty task.reload.mentioned_kis
    end
  end

  test "POST /tasks/:task_id/dependencies adds a predecessor" do
    a = Task.create!(title: "a", creator: @hans)
    b = Task.create!(title: "b", creator: @hans)

    assert_difference -> { TaskDependency.count }, 1 do
      post "/tasks/#{b.id}/dependencies", params: { predecessor_id: a.id }
    end
    assert_includes b.predecessors, a
  end

  test "DELETE /tasks/:task_id/dependencies/:id removes predecessor" do
    a = Task.create!(title: "a", creator: @hans)
    b = Task.create!(title: "b", creator: @hans)
    dep = TaskDependency.create!(predecessor: a, successor: b)

    assert_difference -> { TaskDependency.count }, -1 do
      delete "/tasks/#{b.id}/dependencies/#{dep.id}"
    end
  end

  test "GET /tasks/suggest filters by title and exclude_ids" do
    a = Task.create!(title: "Alpha", creator: @hans)
    b = Task.create!(title: "Alpaca", creator: @hans)
    Task.create!(title: "Beta", creator: @hans)

    get "/tasks/suggest", params: { q: "alp" }
    items = JSON.parse(@response.body)["items"]
    assert_equal 2, items.size
    assert_equal [a.id, b.id].sort, items.map { |i| i["id"] }.sort

    get "/tasks/suggest", params: { q: "alp", exclude_ids: a.id.to_s }
    items = JSON.parse(@response.body)["items"]
    assert_equal [b.id], items.map { |i| i["id"] }
  end

  test "POST /topics/:slug/reorder_tasks sets positions and returns turbo_stream" do
    topic = Topic.create!(name: "T", slug: "t-#{SecureRandom.hex(3)}", creator: @hans)
    t1 = Task.create!(title: "1", creator: @hans)
    t2 = Task.create!(title: "2", creator: @hans)
    TaskTopic.create!(task: t1, topic: topic, position: 1)
    TaskTopic.create!(task: t2, topic: topic, position: 2)

    post "/topics/#{topic.slug}/reorder_tasks",
         params: { ordered_task_ids: "#{t2.id},#{t1.id}" },
         headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_response :ok
    assert_equal 1, TaskTopic.find_by(task: t2, topic: topic).position
    assert_equal 2, TaskTopic.find_by(task: t1, topic: topic).position
  end

  test "DELETE /tasks/:task_id/topics/:id accepts slug as :id" do
    task  = Task.create!(title: "t", creator: @hans)
    topic = Topic.create!(name: "T", slug: "t-#{SecureRandom.hex(3)}", creator: @hans)
    TaskTopic.create!(task: task, topic: topic, position: 1)

    delete "/tasks/#{task.id}/topics/#{topic.slug}"
    assert_empty task.reload.topics
  end

  test "POST /topics/:slug/next_step sets the flag on TaskTopic" do
    topic = Topic.create!(name: "T", slug: "t-#{SecureRandom.hex(3)}", creator: @hans)
    a = Task.create!(title: "a", creator: @hans)
    b = Task.create!(title: "b", creator: @hans)
    TaskTopic.create!(task: a, topic: topic, position: 1)
    TaskTopic.create!(task: b, topic: topic, position: 2)

    post "/topics/#{topic.slug}/next_step",
         params: { task_id: a.id },
         headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_response :ok
    assert TaskTopic.find_by(task: a, topic: topic).next_step
    refute TaskTopic.find_by(task: b, topic: topic).next_step
  end

  test "POST /topics/:slug/next_step replaces existing next_step" do
    topic = Topic.create!(name: "T", slug: "t-#{SecureRandom.hex(3)}", creator: @hans)
    a = Task.create!(title: "a", creator: @hans)
    b = Task.create!(title: "b", creator: @hans)
    TaskTopic.create!(task: a, topic: topic, position: 1, next_step: true)
    TaskTopic.create!(task: b, topic: topic, position: 2)

    post "/topics/#{topic.slug}/next_step",
         params: { task_id: b.id },
         headers: { "Accept" => "text/vnd.turbo-stream.html" }
    refute TaskTopic.find_by(task: a, topic: topic).next_step
    assert TaskTopic.find_by(task: b, topic: topic).next_step
  end

  test "DELETE /topics/:slug/next_step moves task back to first position" do
    topic = Topic.create!(name: "T", slug: "t-#{SecureRandom.hex(3)}", creator: @hans)
    a = Task.create!(title: "a", creator: @hans)
    b = Task.create!(title: "b", creator: @hans)
    TaskTopic.create!(task: a, topic: topic, position: 1)
    TaskTopic.create!(task: b, topic: topic, position: 2, next_step: true)

    delete "/topics/#{topic.slug}/next_step",
           headers: { "Accept" => "text/vnd.turbo-stream.html" }
    refute TaskTopic.find_by(task: b, topic: topic).next_step
    assert_equal 1, TaskTopic.find_by(task: b, topic: topic).position
    assert_equal 2, TaskTopic.find_by(task: a, topic: topic).position
  end

  test "Task marked done auto-clears its next_step flag" do
    topic = Topic.create!(name: "T", slug: "t-#{SecureRandom.hex(3)}", creator: @hans)
    task = Task.create!(title: "x", creator: @hans)
    tt = TaskTopic.create!(task: task, topic: topic, position: 1, next_step: true)

    task.toggle_done!
    refute tt.reload.next_step
  end

  test "POST /tasks with section_target+commitment creates task in that section" do
    assert_difference -> { Task.count }, 1 do
      post "/tasks",
           params: { title: "Schnell für Heute", section_target: "today", commitment: "today" },
           headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end
    task = Task.order(:id).last
    assert_equal "Schnell für Heute", task.title
    assert_equal "today", task.commitment
    assert_equal @hans.id, task.assignee_id
    # Stream zielt auf die Heute-Sektion
    assert_includes @response.body, "tasks_section_today"
    assert_includes @response.body, "section_quickadd_today"
  end

  test "POST /tasks with section_target=inbox creates task without commitment" do
    post "/tasks",
         params: { title: "Triage später", section_target: "inbox" },
         headers: { "Accept" => "text/vnd.turbo-stream.html" }
    task = Task.order(:id).last
    assert_equal "Triage später", task.title
    assert_nil task.commitment
    assert_includes @response.body, "tasks_section_inbox"
  end

  test "POST /tasks/:id/set_commitment moves task between sections" do
    task = Task.create!(title: "x", creator: @hans, assignee: @hans)
    post "/tasks/#{task.id}/set_commitment",
         params: { commitment: "today" },
         headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_response :ok
    assert_equal "today", task.reload.commitment
    # #737 (Hans): die neu gerenderte Row muss den Plus-Button (Append-an-
    # Stack) behalten — er haengt an blade_kind/blade_id, die der Re-Render
    # mitgeben muss. Vorher fehlten sie und der Plus verschwand.
    assert_includes @response.body, "append_to_substack",
                    "Plus-Button (Append) darf beim Wann-Wechsel nicht aus der Row fallen"
  end

  test "POST /tasks/:id/set_commitment with inbox sets commitment to nil" do
    task = Task.create!(title: "x", creator: @hans, assignee: @hans, commitment: :soon)
    post "/tasks/#{task.id}/set_commitment",
         params: { commitment: "inbox" },
         headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_nil task.reload.commitment
  end

  test "Task update writes audit log with Current.actor set" do
    task = Task.create!(title: "t", creator: @hans)
    assert_difference -> { AuditLog.where(auditable: task).count }, 1 do
      patch "/tasks/#{task.id}", params: { task: { status: "done" } }
    end
    log = AuditLog.where(auditable: task).order(:created_at).last
    assert_equal "updated", log.action
    assert_equal @hans.id, log.actor_id
    assert_includes log.changes_data.keys, "status"
  end

  # ─── toggle_done ─────────────────────────────────────────────────────

  test "POST /tasks/:id/toggle_done flippt status open↔done" do
    t = Task.create!(title: "tt", creator: @hans, assignee: @hans, status: :open)
    post "/tasks/#{t.id}/toggle_done",
         headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_response :success
    assert_equal "done", t.reload.status
    post "/tasks/#{t.id}/toggle_done",
         headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_equal "open", t.reload.status
  end

  # ─── #167 publish ────────────────────────────────────────────────────

  test "POST /tasks/:id/publish setzt published_at" do
    t = Task.create!(title: "Entwurf", creator: @hans, assignee: @hans, status: :open)
    t.update!(published_at: nil)
    post "/tasks/#{t.id}/publish",
         headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_response :success
    assert_not_nil t.reload.published_at
  end

  # #756 (Hans, 2026-06-22): publish liefert einen turbo_stream, der das
  # Status-Icon in der Card-Toolbar live austauscht (globe → pause).
  test "POST /tasks/:id/publish tauscht das Toolbar-Status-Control live (globe -> pause)" do
    t = Task.create!(title: "Entwurf", creator: @hans, assignee: @hans, status: :open, published_at: nil)
    post "/tasks/#{t.id}/publish",
         headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_response :success
    # Der Stream ersetzt den stabilen Control-Span und zeigt jetzt die
    # Auf-Entwurf-Aktion (unpublish) statt der Veröffentlichen-Aktion.
    assert_match %r{<turbo-stream action="replace"[^>]*targets="#task_status_control_#{t.id}"}, @response.body
    assert_match %r{/tasks/#{t.id}/unpublish}, @response.body
    refute_match %r{data-task-publish}, @response.body
  end

  # #397 (Hans, 2026-05-28): leerer description-Param darf eine
  # gespeicherte Beschreibung NICHT wegputzen.
  test "POST /tasks/:id/publish ueberschreibt non-empty description nicht mit leerem Param" do
    t = Task.create!(title: "Entwurf", creator: @hans, assignee: @hans, status: :open,
                     description: "Gespeicherte Beschreibung", published_at: nil)
    post "/tasks/#{t.id}/publish",
         params: { description: "" },
         headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_response :success
    assert_equal "Gespeicherte Beschreibung", t.reload.description
    assert_not_nil t.published_at
  end

  # ─── create_awaiting ─────────────────────────────────────────────────

  test "POST /tasks/:id/create_awaiting legt Awaiting an, mit Topics vom Task" do
    grant(@hans, "Awaiting", %w[read create update delete])
    topic = create_topic(creator: @hans)
    t = Task.create!(title: "Mit Awaiting", creator: @hans, assignee: @hans)
    TaskTopic.create!(task: t, topic: topic)
    assert_difference -> { Awaiting.count }, 1 do
      post "/tasks/#{t.id}/create_awaiting",
           params: { description: "Worauf wartest Du?" }
    end
    a = Awaiting.last
    assert_equal "Worauf wartest Du?", a.title
    assert_equal t.id, a.task_id
    assert_includes a.topics, topic
    assert_redirected_to awaiting_path(a)
  end

  test "create_awaiting nutzt Fallback-Title wenn keine Description" do
    grant(@hans, "Awaiting", %w[read create update delete])
    t = Task.create!(title: "MeinTask", creator: @hans, assignee: @hans)
    post "/tasks/#{t.id}/create_awaiting", params: {}
    a = Awaiting.last
    assert_equal "Ergebnis von: MeinTask", a.title
  end

  # ─── #150 Phase B: promote_to_topic ──────────────────────────────────

  test "POST /tasks/:id/promote_to_topic wandelt Task in Topic um" do
    grant(@hans, "Topic", %w[read create update delete])
    t = Task.create!(title: "Task → Topic", creator: @hans, assignee: @hans)
    assert_difference -> { Topic.count }, 1 do
      post "/tasks/#{t.id}/promote_to_topic"
    end
    topic = Topic.last
    assert_equal "Task → Topic", topic.name
    assert_redirected_to topic_path(topic)
  end

  # ─── #162 suggest_tags ───────────────────────────────────────────────

  test "GET /tasks/suggest_tags liefert vorhandene Tags als JSON" do
    Task.create!(title: "A", creator: @hans, tags: %w[urgent prio])
    Task.create!(title: "B", creator: @hans, tags: %w[urgent])
    get "/tasks/suggest_tags",
        headers: { "Accept" => "application/json" }
    assert_response :success
    data = JSON.parse(@response.body)
    slugs = data["items"].map { |i| i["slug"] }
    assert_includes slugs, "urgent"
    assert_includes slugs, "prio"
  end

  # ─── new / edit (Render-Tests) ───────────────────────────────────────

  test "GET /tasks/new rendert das Task-Form" do
    get "/tasks/new"
    assert_response :success
    assert_select "form[action='/tasks']"
  end

  test "GET /tasks/:id/edit rendert vorbelegtes Form" do
    t = Task.create!(title: "Bestehender Task", creator: @hans, assignee: @hans)
    get "/tasks/#{t.id}/edit"
    assert_response :success
    assert_match(/Bestehender Task/, @response.body)
  end

  # ─── Index-Grouping (#203 Phase E.7) ─────────────────────────────────

  test "GET /tasks gruppiert per Default nach Wann-Stufen (Eingang/Heute/Demnaechst/Spaeter)" do
    Task.create!(title: "I-AAA", creator: @hans, assignee: @hans, commitment: nil)
    Task.create!(title: "H-BBB", creator: @hans, assignee: @hans, commitment: :today)
    Task.create!(title: "S-CCC", creator: @hans, assignee: @hans, commitment: :soon)
    Task.create!(title: "L-DDD", creator: @hans, assignee: @hans, commitment: :later)
    get "/tasks"
    assert_response :success
    body = @response.body
    [%w[I-AAA H-BBB], %w[H-BBB S-CCC], %w[S-CCC L-DDD]].each do |a, b|
      assert body.index(a) < body.index(b),
             "Erwartet, dass #{a} vor #{b} steht (Section-Order)"
    end
  end

  test "GET /tasks?group=topic gruppiert nach Topic und zeigt 'Ohne Projekt' zuerst" do
    a = Topic.create!(name: "Alpha", slug: "alpha-#{SecureRandom.hex(2)}", creator: @hans)
    untopic = Task.create!(title: "OHNETOPIC-XXX", creator: @hans, assignee: @hans)
    in_a    = Task.create!(title: "MITTOPIC-YYY", creator: @hans, assignee: @hans)
    TaskTopic.create!(task: in_a, topic: a)
    get "/tasks?group=topic"
    assert_response :success
    body = @response.body
    assert body.index("OHNETOPIC-XXX") < body.index("MITTOPIC-YYY"),
           "Ohne-Projekt-Section steht vor Topic-Sections"
  end

  test "GET /tasks?by=topic ist Backward-Compat zu group=topic" do
    a = Topic.create!(name: "Beta", slug: "beta-#{SecureRandom.hex(2)}", creator: @hans)
    t = Task.create!(title: "COMPAT-PROBE", creator: @hans, assignee: @hans)
    TaskTopic.create!(task: t, topic: a)
    get "/tasks?by=topic"
    assert_response :success
    assert_includes @response.body, "Beta"
    assert_includes @response.body, "COMPAT-PROBE"
  end

  # #163 Phase 5a-2: Listen-Blade-Fragment fuer Sidebar-Plus + Stack-Restore.
  test "GET /tasks/list_card rendert Listen-Blade ohne Layout" do
    Task.create!(title: "BLADELIST-TASK-XYZ", creator: @hans, assignee: @hans, status: :open)
    get list_card_tasks_path
    assert_response :success
    assert_match %r{data-uuid="list:tasks"}, @response.body
    assert_includes @response.body, "BLADELIST-TASK-XYZ"
    refute_match %r{<html}, @response.body
  end

  # #388 (Hans, 2026-05-28): Batch-Edit von Aufgaben.
  test "POST /tasks/bulk_update setzt Felder fuer alle ids" do
    other = HumanActor.create!(name: "Other", email: "other-#{SecureRandom.hex(2)}@t.local", password: "secretsecret")
    topic = Topic.create!(name: "BulkTopic", slug: "bulk-#{SecureRandom.hex(2)}", creator: @hans)
    t1 = Task.create!(title: "BULK-A", creator: @hans, status: :open)
    t2 = Task.create!(title: "BULK-B", creator: @hans, status: :open)
    t3 = Task.create!(title: "BULK-C", creator: @hans, status: :open)

    post bulk_update_tasks_path,
         params: { ids: [t1.id, t2.id], assignee_id: other.id, status: "done", add_topic_id: topic.id },
         as: :turbo_stream
    assert_response :success

    assert_equal other.id, t1.reload.assignee_id
    assert_equal other.id, t2.reload.assignee_id
    assert_nil   t3.reload.assignee_id
    assert t1.reload.done?
    assert t2.reload.done?
    refute t3.reload.done?
    assert_includes t1.reload.topics.map(&:id), topic.id
    assert_includes t2.reload.topics.map(&:id), topic.id
  end

  test "POST /tasks/bulk_update ohne ids antwortet mit Toast" do
    post bulk_update_tasks_path, params: { status: "done" }, as: :turbo_stream
    assert_response :success
    assert_match(/ausgewaehlt|leer/i, @response.body)
  end

  # #480 Increment 2 (Hans, 2026-06-03): Highlight in der Task-Description.
  test "POST /tasks/:id/wrap_highlight markiert eine Stelle in der Description" do
    task = Task.create!(creator: @hans, title: "HL", status: :open,
                        description: "Erster Absatz.\n\nZweiter Absatz.")
    post wrap_highlight_task_path(task),
         params: { anchor: "block-2", color: "gelb", selected_text: "Zweiter" },
         headers: { "Accept" => "application/json" }
    assert_response :success
    body = JSON.parse(@response.body)
    assert_match(/\A[a-f0-9]{8}\z/, body["anchor"])
    assert_match(/==gelb\|Zweiter==\^[a-f0-9]{8}/, task.reload.description)
  end

  # #534: ref_label-JSON für die CM6 [[#id]]-Pille.
  test "ref_label liefert found+title für existierende Aufgabe" do
    task = Task.create!(title: "Ziel-Aufgabe", creator: @hans)
    get "/tasks/#{task.id}/ref_label", headers: { "Accept" => "application/json" }
    assert_response :success
    body = JSON.parse(@response.body)
    assert_equal true, body["found"]
    assert_equal task.id, body["id"]
    assert_equal "Ziel-Aufgabe", body["title"]
  end

  test "ref_label antwortet 404 für unbekannte Aufgabe" do
    get "/tasks/99999999/ref_label", headers: { "Accept" => "application/json" }
    assert_response :not_found
  end

  # ── #564: Turbo-Stream-Target-Assertions für die 4 create-Pfade ──────────
  # Die Stream-Targets sind der Vertrag zwischen Controller und den Listen im
  # DOM — ein vertipptes Target rendert ins Leere (Bug-Klasse #557/#558/#563).

  def assert_stream(action, target)
    assert_match Regexp.new(Regexp.escape(%(<turbo-stream action="#{action}" target="#{target}"))),
      @response.body, "Stream #{action}→#{target} fehlt"
  end

  test "create (Default-Pfad): prepend in open_tasks_list + Blade-Append" do
    post "/tasks", params: { task: { title: "Stream-Probe" } },
         headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_response :success
    assert_stream "remove",  "tasks_empty"
    assert_stream "prepend", "open_tasks_list"
    assert_stream "append",  "blade_stack_container"
  end

  test "create (agent_target): prepend in Agent-Liste + Quickadd-Reset" do
    agent = create_agent
    post "/tasks", params: { task: { title: "Agent-Probe" }, agent_target: agent.id },
         headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_response :success
    assert_stream "remove",  "agent_tasks_empty_#{agent.id}"
    assert_stream "prepend", "agent_tasks_#{agent.id}"
    assert_stream "replace", "agent_quickadd_#{agent.id}"
    assert_stream "append",  "blade_stack_container"
  end

  test "create (section_target): prepend in Sektionsliste + Form-Reset" do
    post "/tasks", params: { task: { title: "Sektion-Probe" }, section_target: "today" },
         headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_response :success
    assert_stream "prepend", "tasks_section_today"
    assert_stream "replace", "section_quickadd_today_none"
    assert_stream "append",  "blade_stack_container"
  end

  test "create (Subtask): replaceAll auf das Eltern-Detail" do
    parent = Task.create!(title: "Eltern", creator: @hans, status: :open)
    post "/tasks", params: { task: { title: "Kind", parent_id: parent.id } },
         headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_response :success
    # replace_all serialisiert als action="replace" + targets-Selektor.
    assert_match %r{<turbo-stream action="replace" targets="#task_#{parent.id}"}, @response.body
  end
  # ── #572: Meilenstein-UI ───────────────────────────────────────────────────
  test "toggle_milestone: live Rot/Grau-Wechsel + Rauten-Row, nur Projekt-Tasks zeigen das Icon" do
    kunde = KnowledgeItem.create!(uuid: SecureRandom.uuid, title: "MS-Kunde",
                                  item_type: :organization, creator: @hans,
                                  file_path: "x/ms.md", content_hash: "h", body: "")
    projekt = Topic.create!(name: "MS-Projekt", slug: "ms-#{SecureRandom.hex(3)}",
                            creator: @hans, customer_uuid: kunde.uuid)
    task = Task.create!(title: "MS-Task", creator: @hans, status: :open)
    TaskTopic.create!(task: task, topic: projekt, position: 1)

    # Icon in der Blade-Leiste (grau, Umriss)
    get "/tasks/#{task.id}/card"
    assert_includes @response.body, "task_milestone_btn_#{task.id}"
    assert_includes @response.body, "toggle_milestone"

    # Toggle → rot + Row-Replace (Raute)
    post "/tasks/#{task.id}/toggle_milestone", headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_response :success
    assert task.reload.client_milestone
    assert_match %r{<turbo-stream action="replace" target="task_milestone_btn_#{task.id}"}, @response.body
    assert_includes @response.body, "text-rose-600"
    assert_match %r{<turbo-stream action="replace" target="task_row_#{task.id}"}, @response.body
    assert_includes @response.body, "rotate-45", "Row muss den Rauten-Marker tragen"

    # Nicht-Projekt-Task: kein sichtbares Icon (nur hidden-Platzhalter)
    plain = Task.create!(title: "Normal", creator: @hans, status: :open)
    get "/tasks/#{plain.id}/card"
    refute_includes @response.body, "toggle_milestone"
  end

  test "Listen-Filter Art: Alle | Aufgaben | Meilensteine" do
    t1 = Task.create!(title: "Filter-Normalaufgabe", creator: @hans, status: :open, assignee: @hans)
    t2 = Task.create!(title: "Filter-Meilenstein", creator: @hans, status: :open, assignee: @hans,
                      client_milestone: true)

    get "/tasks/list_card", params: { kind: "milestones" }
    assert_includes @response.body, "Filter-Meilenstein"
    refute_includes @response.body, "Filter-Normalaufgabe"

    get "/tasks/list_card", params: { kind: "tasks" }
    assert_includes @response.body, "Filter-Normalaufgabe"
    refute_includes @response.body, "Filter-Meilenstein"

    get "/tasks/list_card"
    assert_includes @response.body, "Filter-Normalaufgabe"
    assert_includes @response.body, "Filter-Meilenstein"
  end

  # ─── #953: Backlinks-Sektion im Task-Detail ───────────────────────────
  test "card zeigt Backlinks: KIs, die die Aufgabe per [[#id]] referenzieren" do
    grant(@hans, "KnowledgeItem", %w[read create update])
    with_isolated_miolimos_base do
      task = Task.create!(title: "Backlink-Ziel", creator: @hans)
      FileProxy.create(actor: @hans, title: "Notiz mit Verweis", item_type: :note,
                       content: "Siehe [[##{task.id}]].")
      get "/tasks/#{task.id}/card"
      assert_response :success
      assert_includes @response.body, "tasks.#{task.id}.backlinks"
      assert_includes @response.body, "Notiz mit Verweis"
    end
  end

  test "card: eigene Antworten der Aufgabe zählen nicht als Backlink" do
    grant(@hans, "KnowledgeItem", %w[read create update])
    with_isolated_miolimos_base do
      task  = Task.create!(title: "Selbstverweis-Probe", creator: @hans)
      reply = FileProxy.create(actor: @hans, title: "tmp-reply", item_type: :reply,
                               content: "hier [[##{task.id}]]")
      reply.update!(title: nil, parent_type: "Task", parent_id_int: task.id,
                    published_at: Time.current)
      get "/tasks/#{task.id}/card"
      assert_response :success
      refute_includes @response.body, "tasks.#{task.id}.backlinks"
    end
  end

  # #953 Folge: auch Task-BESCHREIBUNGEN sind Backlink-Quellen.
  test "card: Beschreibung einer anderen Aufgabe erscheint als Backlink" do
    grant(@hans, "KnowledgeItem", %w[read create update])
    with_isolated_miolimos_base do
      ziel   = Task.create!(title: "Desc-Backlink-Ziel", creator: @hans)
      quelle = Task.create!(title: "Desc-Quelle", creator: @hans,
                            description: "hängt an [[##{ziel.id}]]")
      get "/tasks/#{ziel.id}/card"
      assert_response :success
      assert_includes @response.body, "tasks.#{ziel.id}.backlinks"
      assert_includes @response.body, "##{quelle.id} Desc-Quelle"
    end
  end

  test "KI-Card: Aufgabe mit [[Titel]]-Link in der Beschreibung erscheint als Backlink" do
    grant(@hans, "KnowledgeItem", %w[read create update])
    with_isolated_miolimos_base do
      ki     = FileProxy.create(actor: @hans, title: "Panel-Ziel-Notiz", item_type: :note, content: "x")
      quelle = Task.create!(title: "KI-Verweis-Aufgabe", creator: @hans,
                            description: "siehe [[Panel-Ziel-Notiz]]")
      get "/knowledge_items/#{ki.uuid}/card"
      assert_response :success
      assert_includes @response.body, "##{quelle.id} KI-Verweis-Aufgabe"
    end
  end

  test "card: Antwort einer ANDEREN Aufgabe erscheint als Backlink „Titel: Antwort“" do
    grant(@hans, "KnowledgeItem", %w[read create update])
    with_isolated_miolimos_base do
      target = Task.create!(title: "Backlink-Ziel-B", creator: @hans)
      andere = Task.create!(title: "Quell-Aufgabe", creator: @hans)
      reply  = FileProxy.create(actor: @hans, title: "tmp-reply2", item_type: :reply,
                                content: "vgl. [[##{target.id}]]")
      reply.update!(title: nil, parent_type: "Task", parent_id_int: andere.id,
                    published_at: Time.current)
      get "/tasks/#{target.id}/card"
      assert_response :success
      assert_includes @response.body, "Quell-Aufgabe: Antwort"
    end
  end
end
