require "test_helper"

# #378 Phase 7 (Hans, 2026-05-26): Tests fuer TaskTemplatesController —
# Picker-Suggest fuer Quickadd.
class TaskTemplatesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @hans = HumanActor.create!(
      name: "Hans", email: "hans-tt-#{SecureRandom.hex(3)}@t.local",
      password: "secretsecret"
    )
    grant(@hans, "Task", %w[read create update delete])
    post "/login", params: { email: @hans.email, password: "secretsecret" }
  end

  test "GET /task_templates/suggest returns matching templates as JSON" do
    t1 = TaskTemplate.create!(title: "Recherche durchfuehren", description: "x")
    TaskTemplate.create!(title: "Anderes ganz")
    get "/task_templates/suggest", params: { q: "recherche" }
    assert_response :success
    json = JSON.parse(response.body)
    titles = json.map { |h| h["title"] }
    assert_includes titles, "Recherche durchfuehren"
    refute_includes titles, "Anderes ganz"
  end

  test "GET /task_templates/suggest with empty q returns all (limit 8)" do
    10.times { |i| TaskTemplate.create!(title: "Template #{i}") }
    get "/task_templates/suggest", params: { q: "" }
    assert_response :success
    json = JSON.parse(response.body)
    assert_equal 8, json.size
  end

  test "GET /task_templates/suggest with agent_id excludes templates for other agents" do
    a1 = AgentActor.create!(name: "A1", email: "a1-#{SecureRandom.hex(3)}@x.l",
                              description: "x")
    a2 = AgentActor.create!(name: "A2", email: "a2-#{SecureRandom.hex(3)}@x.l",
                              description: "x")
    yes   = TaskTemplate.create!(title: "Match", agent_actor_id: a1.id)
    other = TaskTemplate.create!(title: "Skip",  agent_actor_id: a2.id)
    global = TaskTemplate.create!(title: "Global", agent_actor_id: nil)
    get "/task_templates/suggest", params: { agent_id: a1.id }
    json = JSON.parse(response.body)
    ids = json.map { |h| h["id"] }
    assert_includes ids, yes.id
    assert_includes ids, global.id, "globale Vorlagen werden mit ausgeliefert"
    refute_includes ids, other.id
  end
end
