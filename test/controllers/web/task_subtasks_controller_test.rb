require "test_helper"

class TaskSubtasksControllerTest < ActionDispatch::IntegrationTest
  setup do
    @hans = HumanActor.create!(
      name: "Hans", email: "hans-tsub-#{SecureRandom.hex(3)}@t.local",
      password: "secretsecret"
    )
    grant(@hans, "Task", %w[read create update delete])
    post "/login", params: { email: @hans.email, password: "secretsecret" }

    @parent = Task.create!(title: "Eltern", creator: @hans, assignee: @hans, status: :open)
  end

  test "POST with child_id reparents existing task and inherits topics" do
    topic = Topic.create!(slug: "ss-#{SecureRandom.hex(3)}", name: "Foo",
                          creator: @hans, status: :active, template: false)
    TaskTopic.create!(task: @parent, topic: topic, position: 1)
    child = Task.create!(title: "Kind", creator: @hans, assignee: @hans, status: :open)

    post "/tasks/#{@parent.id}/subtasks",
         params: { child_id: child.id },
         headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_response :ok
    assert_equal @parent.id, child.reload.parent_id
    assert_includes child.topics, topic
    assert_includes @response.body, "task_subtasks_chips_#{@parent.id}"
  end

  test "POST with create_with creates new subtask under parent" do
    assert_difference -> { Task.count }, 1 do
      post "/tasks/#{@parent.id}/subtasks",
           params: { create_with: "Neues Kind" },
           headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end
    new_child = Task.where(title: "Neues Kind").first
    assert_equal @parent.id, new_child.parent_id
    assert_equal @hans.id, new_child.creator_id
  end

  test "DELETE detaches child from parent (does not destroy)" do
    child = Task.create!(title: "Kind", creator: @hans, assignee: @hans,
                         parent: @parent, status: :open)
    assert_no_difference -> { Task.count } do
      delete "/tasks/#{@parent.id}/subtasks/#{child.id}",
             headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end
    assert_response :ok
    assert_nil child.reload.parent_id
    assert_includes @response.body, "toast_stack"
    assert_includes @response.body, "Kind"
  end
end
