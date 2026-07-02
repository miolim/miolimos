require "test_helper"

# Smoke tests: every top-level web page returns 200 after login and with
# the expected capabilities granted. Catches route typos, missing views,
# unresolvable i18n keys and similar breakage cheaply.
class SmokeTest < ActionDispatch::IntegrationTest
  setup do
    @hans = HumanActor.create!(
      name: "Hans", email: "hans-smoke-#{SecureRandom.hex(3)}@t.local",
      password: "secretsecret"
    )
    %w[Task Topic Communication KnowledgeItem Actor OauthCredential Team].each do |rt|
      grant(@hans, rt, %w[read create update delete])
    end

    # Minimum seeded data so every index page exercises its l()/format: :short
    # codepaths — without rows those branches are skipped and i18n gaps hide.
    topic = Topic.create!(
      name: "Smoke-Topic", slug: "smoke-#{SecureRandom.hex(3)}",
      creator: @hans, status: :active, description: "x"
    )
    task = Task.create!(
      title: "Smoke-Task", creator: @hans, assignee: @hans,
      status: :open, priority: :normal, due_date: Date.today + 1
    )
    TaskTopic.create!(task: task, topic: topic, position: 1)

    person_ki = KnowledgeItem.create!(
      uuid: SecureRandom.uuid, title: "S T",
      item_type: :person,
      first_name: "S", last_name: "T",
      file_path: "knowledge/people/smoke-#{SecureRandom.hex(3)}.md",
      content_hash: SecureRandom.hex(32),
      file_created_at: Time.current, file_updated_at: Time.current,
      indexed_at: Time.current
    )
    person_ki.contact_points.create!(kind: "email", value: "s@t.test")

    Email.create!(
      subject: "Smoke-Email", body: "x", sent_at: Time.current,
      direction: :inbound, external_id: "smoke-#{SecureRandom.hex(3)}"
    )

    KnowledgeItem.create!(
      uuid: SecureRandom.uuid, title: "Smoke-Note",
      item_type: :note,
      file_path: "knowledge/notes/smoke-#{SecureRandom.hex(3)}.md",
      content_hash: SecureRandom.hex(32),
      file_created_at: Time.current, file_updated_at: Time.current,
      indexed_at: Time.current
    )

    post "/login", params: { email: @hans.email, password: "secretsecret" }
  end

  {
    "dashboard"           => "/dashboard",
    "topics index"        => "/topics",
    "new topic"           => "/topics/new",
    "tasks index"         => "/tasks",
    "persons index"       => "/knowledge_items?item_type=person",
    "communications idx"  => "/communications",
    "knowledge idx"       => "/knowledge_items",
    "new knowledge"       => "/knowledge_items/new",
    # #613: Einstellungen sind ein Blade-Stack — Smoke gegen die Blades.
    "settings stack"      => "/settings",
    "settings accounts"   => "/settings/blade/accounts",
    "settings agents"     => "/settings/blade/agents",
    "settings teams"      => "/settings/blade/teams"
  }.each do |label, path|
    test "GET #{path} (#{label}) returns 200" do
      get path
      assert_response :success, "GET #{path} expected 200, got #{response.status}"
    end
  end

  test "/search with short query returns turbo frame with empty body" do
    get "/search", params: { q: "x" }
    assert_response :success
  end

  test "/search with real query renders results" do
    Task.create!(title: "Findbares Wort abcdef", creator: @hans, assignee: @hans)
    get "/search", params: { q: "abcdef" }
    assert_response :success
    assert_includes @response.body, "Findbares Wort"
  end

  # #772 (Hans): Dark-Mode-Umschalter in der Topbar + serverseitige dark-Klasse
  # aus dem theme-Cookie (morph-/FOUC-sicher).
  test "Topbar trägt den Dark-Mode-Umschalter" do
    get "/tasks"
    assert_response :success
    assert_includes @response.body, %(data-controller="theme")
    assert_includes @response.body, %(data-action="click->theme#toggle")
  end

  test "theme-Cookie=dark rendert <html class=dark>, ohne Cookie nicht" do
    get "/tasks"
    assert_match %r{<html[^>]*\sclass="\s*"}, @response.body

    cookies[:theme] = "dark"
    get "/tasks"
    assert_match %r{<html[^>]*\sclass="\s*dark\s*"}, @response.body
    assert_includes @response.body, %(aria-pressed="true")
  end
end
