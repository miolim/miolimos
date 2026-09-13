require "test_helper"

# #1582 (Hans): „Man soll festlegen können, welcher Stack beim Programmstart
# als erstes angezeigt wird." Programmstart = `/` und der Login ohne Deep-Link;
# der Dashboard-Eintrag der Seitenleiste bleibt das Dashboard.
class StartControllerTest < ActionDispatch::IntegrationTest
  setup do
    @hans = HumanActor.create!(name: "Hans", email: "start-#{SecureRandom.hex(3)}@t.local",
                               password: "secretsecret")
    grant(@hans, "Task", %w[read])
    grant(@hans, "Topic", %w[read])
    grant(@hans, "KnowledgeItem", %w[read])
    grant(@hans, "Communication", %w[read])
  end

  def login
    post "/login", params: { email: @hans.email, password: "secretsecret" }
  end

  test "ohne Wahl führt der Start aufs Dashboard" do
    login
    assert_redirected_to "/dashboard"

    get "/"
    assert_redirected_to "/dashboard"
  end

  test "gewählte Seite ist Ziel von / und vom Login" do
    @hans.update_preferences("start_stack" => "tasks")

    login
    assert_redirected_to "/tasks"

    get "/"
    assert_redirected_to "/tasks"
  end

  test "Deep-Link gewinnt beim Login" do
    @hans.update_preferences("start_stack" => "tasks")
    get "/knowledge_items"
    login
    assert_redirected_to "/knowledge_items"
  end

  test "ohne Sitzung führt / über den Login zur gewählten Seite" do
    @hans.update_preferences("start_stack" => "tasks")
    get "/"
    assert_redirected_to "/login"

    login
    follow_redirect!
    assert_redirected_to "/tasks"
  end

  test "leerer Start rendert das Dashboard ohne Card und ohne Wiederherstellen" do
    @hans.update_preferences("start_stack" => "empty")
    login
    task = Task.create!(title: "Aus-dem-Snapshot", creator: @hans, assignee: @hans, status: :open)
    StackSnapshot.record!(actor: @hans, history_key: DashboardController::LIST_HISTORY_KEY,
                          trail: [["list:dashboard", "task:#{task.id}"]], current: 0)

    get "/"
    assert_redirected_to "/dashboard?start=empty"

    follow_redirect!
    assert_response :success
    assert_includes @response.body, 'data-blade-stack-start-empty-value="true"'
    refute_includes @response.body, 'data-uuid="list:dashboard"'
    refute_includes @response.body, "data-uuid=\"task:#{task.id}\"", "der Snapshot darf nicht zurückkommen"
    refute_includes @response.body, 'data-blade-stack-server-restored-value="true"'
  end

  test "jede wählbare Seite hat ein eigenes Ziel" do
    login
    (ActorPreferences::START_STACK_OPTIONS - %w[dashboard empty]).each do |option|
      @hans.update_preferences("start_stack" => option)
      get "/"
      assert_response :redirect, option
      refute_match %r{/dashboard\z}, response.location, "#{option} darf nicht aufs Dashboard fallen"
    end
  end

  test "Dashboard aus der Seitenleiste bleibt das Dashboard" do
    @hans.update_preferences("start_stack" => "empty")
    login

    get "/dashboard"
    assert_response :success
    refute_includes @response.body, 'data-blade-stack-start-empty-value="true"'
  end
end
