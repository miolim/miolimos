require "test_helper"

class DashboardControllerTest < ActionDispatch::IntegrationTest
  setup do
    @hans = HumanActor.create!(
      name: "Hans", email: "hans-#{SecureRandom.hex(3)}@t.local",
      password: "secretsecret"
    )
    grant(@hans, "Task", %w[read])
    grant(@hans, "Topic", %w[read])
    grant(@hans, "Contact", %w[read])
    grant(@hans, "KnowledgeItem", %w[read])
    grant(@hans, "Communication", %w[read])

    login_as(@hans)
  end

  def login_as(actor)
    post "/login", params: { email: actor.email, password: "secretsecret" }
  end

  test "GET /dashboard shows my today and soon tasks" do
    Task.create!(title: "Heute-Aufgabe", creator: @hans, assignee: @hans,
                 status: :open, commitment: :today)
    Task.create!(title: "Demnächst-Aufgabe", creator: @hans, assignee: @hans,
                 status: :open, commitment: :soon)
    Task.create!(title: "Später-Aufgabe", creator: @hans, assignee: @hans,
                 status: :open, commitment: :later)
    Task.create!(title: "Fremde-Aufgabe", creator: @hans, status: :open,
                 commitment: :today)

    get "/dashboard"
    assert_response :success
    assert_includes @response.body, "Heute-Aufgabe"
    assert_includes @response.body, "Demnächst-Aufgabe"
    refute_includes @response.body, "Später-Aufgabe"
    refute_includes @response.body, "Fremde-Aufgabe"
  end

  test "GET /dashboard excludes tasks in terminal status" do
    # Eindeutiger Titel, der nicht mit dem "Erledigte anzeigen"-Filter-Link kollidiert
    Task.create!(title: "Schon-fertig-abcdef", creator: @hans, assignee: @hans,
                 status: :done, commitment: :today)
    get "/dashboard"
    refute_includes @response.body, "Schon-fertig-abcdef"
  end

  test "GET /dashboard requires Task read capability" do
    Capability.where(actor: @hans, resource_type: "Task").destroy_all
    get "/dashboard"
    assert_response :forbidden
  end

  # #214 / #163 Phase 5b-2: das rechte Pane ist jetzt ein blade-stack.
  # `?task=X` (Legacy) wird zu `?stack=task:X` umgemappt und rendert die
  # Task-Blade-Card serverseitig im Stack.
  test "GET /dashboard?task=X rendert die Task als Blade-Card im Stack" do
    grant(@hans, "Awaiting", %w[read])
    task = Task.create!(title: "Inline-im-Dashboard-Title", creator: @hans, assignee: @hans)
    get "/dashboard?task=#{task.id}"
    assert_response :success
    assert_includes @response.body, "Inline-im-Dashboard-Title",
                    "Task-Title muss im Dashboard-Body stehen"
    assert_match %r{data-uuid="task:#{task.id}"}, @response.body,
                 "Task-Blade muss mit data-uuid=task:<id> im Stack auftauchen"
  end

  test "GET /dashboard?task=nicht-existent rendert nur list:dashboard-Blade ohne Fehler" do
    get "/dashboard?task=999999"
    assert_response :success
    refute_match %r{Inline-im-Dashboard-Title}, @response.body
    # #163 Phase 6c: /dashboard ist ein Blade-Stack. Default ist
    # list:dashboard; eine nicht-existente Task wird stillschweigend
    # uebergangen, die Listen-Blade bleibt sichtbar.
    assert_match %r{data-uuid="list:dashboard"}, @response.body
    refute_match %r{data-uuid="task:999999"}, @response.body
  end

  # #163 Phase 5b-2: gemischter Stack via ?stack= Param.
  test "GET /dashboard?stack=task:X,awaiting:Y rendert beide als Blades" do
    grant(@hans, "Awaiting", %w[read])
    task     = Task.create!(title: "Mixed-Stack-Task", creator: @hans, assignee: @hans)
    awaiting = Awaiting.create!(title: "Mixed-Stack-Awaiting", creator: @hans, follow_up_at: Date.tomorrow)
    get "/dashboard?stack=task:#{task.id},awaiting:#{awaiting.id}"
    assert_response :success
    assert_match %r{data-uuid="task:#{task.id}"},         @response.body
    assert_match %r{data-uuid="awaiting:#{awaiting.id}"}, @response.body
  end

  # #434 (Hans, 2026-06-01): Standalone-Card des list:dashboard-Blades.
  # Ohne diesen Endpoint konnte der Stack-Restore (Verlauf-Drawer) das
  # erste Blade (Dashboard) nicht wieder aufbauen — der Fetch lief in 404.
  test "GET /dashboard/list_card rendert das list:dashboard-Blade ohne Layout" do
    Task.create!(title: "LISTCARD-HEUTE-PROBE", creator: @hans, assignee: @hans,
                 status: :open, commitment: :today)
    get dashboard_list_card_path
    assert_response :success
    assert_match %r{data-uuid="list:dashboard"}, @response.body
    assert_match %r{class="[^"]*stack-card}, @response.body
    assert_includes @response.body, "LISTCARD-HEUTE-PROBE"
    refute_match %r{<html}, @response.body
  end

  test "GET /dashboard/list_card requires Task read capability" do
    Capability.where(actor: @hans, resource_type: "Task").destroy_all
    get dashboard_list_card_path
    assert_response :forbidden
  end

  # #457 (Hans, 2026-06-02): Agent-Aktivitaet je Aufgabe zusammengefasst —
  # eine Zeile pro Task (juengste Aktivitaet) mit Gesamtzahl (##).
  test "Agent-Aktivität fasst mehrere Aktivitaeten je Aufgabe zusammen" do
    agent = AgentActor.create!(name: "Aktiv", description: "agent",
                               email: "aktiv-#{SecureRandom.hex(3)}@miolim.de",
                               show_in_dashboard: true)
    grant(agent, "KnowledgeItem", %w[read create update delete])
    task = Task.create!(title: "AKTIV-TASK-XYZ", description: "d",
                        creator: @hans, assignee: agent, status: :open)
    task.update_column(:published_at, Time.current)
    2.times do |i|
      r = FileProxy.create(actor: agent, title: "r#{i}", item_type: :reply, content: "antwort #{i}")
      r.update!(title: nil, parent_type: "Task", parent_id_int: task.id,
                published_at: Time.current + i.seconds)
    end
    get "/dashboard"
    assert_response :success
    # Zwei Aktivitaeten derselben Task -> eine Zeile mit Gesamtzahl (2).
    assert_includes @response.body, "(2)"
  end

  # #214 follow-up + 5b-2: Klick auf eine Task-Row im Dashboard appendet
  # die Task als Blade ans rechte Pane (via blade-link Window-Event).
  # Der Title-Link bekommt blade-link-Attribute + href=/tasks/X (fuer
  # Right-Click/Bookmark).
  test "Task-Rows im Dashboard tragen blade-link-Attribute" do
    task = Task.create!(title: "Dashboardlink-Probe-Heute", creator: @hans, assignee: @hans,
                        status: :open, commitment: :today)
    get "/dashboard"
    assert_response :success
    assert_match %r{data-blade-link-kind-value="task"\s+data-blade-link-id-value="#{task.id}"},
                 @response.body,
                 "Task-Row muss blade-link-Markup tragen"
  end
end
