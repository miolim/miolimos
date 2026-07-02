require "test_helper"

# #378 Phase 6 (Hans, 2026-05-26): Tests fuer TaskDependenciesController
# — Predecessor-Kanten zwischen Tasks, mit Cycle-/Self-/Duplikat-Check
# im Model.
class TaskDependenciesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @hans = HumanActor.create!(
      name: "Hans", email: "hans-td-#{SecureRandom.hex(3)}@t.local",
      password: "secretsecret"
    )
    grant(@hans, "Task", %w[read create update delete])
    post "/login", params: { email: @hans.email, password: "secretsecret" }
  end

  test "POST /tasks/:id/dependencies creates a finish_to_start edge" do
    a = create_task(creator: @hans)
    b = create_task(creator: @hans)
    assert_difference -> { TaskDependency.count }, 1 do
      post "/tasks/#{b.id}/dependencies",
           params: { predecessor_id: a.id },
           headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end
    assert_response :success
    dep = TaskDependency.find_by(predecessor: a, successor: b)
    assert dep.finish_to_start?
  end

  test "POST dependencies rejects self-reference (validation in model)" do
    a = create_task(creator: @hans)
    assert_no_difference -> { TaskDependency.count } do
      post "/tasks/#{a.id}/dependencies",
           params: { predecessor_id: a.id },
           headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end
    # Controller swallows RecordInvalid und antwortet mit Stream + alert;
    # response.status bleibt 200, denn das Replacement-Markup wird
    # gerendert. Wichtig: Kein neuer TaskDependency-Datensatz.
    assert_response :success
  end

  test "POST dependencies rejects duplicate edge" do
    a = create_task(creator: @hans)
    b = create_task(creator: @hans)
    TaskDependency.create!(predecessor: a, successor: b)
    assert_no_difference -> { TaskDependency.count } do
      post "/tasks/#{b.id}/dependencies",
           params: { predecessor_id: a.id },
           headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end
  end

  test "POST dependencies rejects cycle" do
    a = create_task(creator: @hans)
    b = create_task(creator: @hans)
    TaskDependency.create!(predecessor: a, successor: b)
    # Versuch: b → a wuerde Cycle bauen
    assert_no_difference -> { TaskDependency.count } do
      post "/tasks/#{a.id}/dependencies",
           params: { predecessor_id: b.id },
           headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end
  end

  test "DELETE dependencies removes the edge and emits toast stream" do
    a = create_task(creator: @hans)
    b = create_task(creator: @hans)
    dep = TaskDependency.create!(predecessor: a, successor: b)
    assert_difference -> { TaskDependency.count }, -1 do
      delete "/tasks/#{b.id}/dependencies/#{dep.id}",
             headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end
    assert_response :success
    assert_includes response.body, "Blockade durch"
  end
end
