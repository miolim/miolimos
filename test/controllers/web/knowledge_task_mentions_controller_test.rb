require "test_helper"

class KnowledgeTaskMentionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @hans = HumanActor.create!(
      name: "Hans", email: "hans-ktm-#{SecureRandom.hex(3)}@t.local",
      password: "secretsecret"
    )
    grant(@hans, "Task",          %w[read create update])
    grant(@hans, "KnowledgeItem", %w[read create update])
    post "/login", params: { email: @hans.email, password: "secretsecret" }
  end

  test "POST with task_id links existing task to KI" do
    with_isolated_miolimos_base do
      ki   = FileProxy.create(actor: @hans, title: "Notiz", item_type: :note, content: "")
      task = Task.create!(title: "Tu", creator: @hans, assignee: @hans, status: :open)

      assert_difference -> { TaskMention.count }, 1 do
        post "/knowledge_items/#{ki.uuid}/task_mentions",
             params: { task_id: task.id },
             headers: { "Accept" => "text/vnd.turbo-stream.html" }
      end
      assert_response :ok
      assert TaskMention.exists?(task: task, mentioned_uuid: ki.uuid)
      assert_includes @response.body, "ki_task_mentions_chips_#{ki.uuid}"
    end
  end

  test "POST with create_with creates new task and links it" do
    with_isolated_miolimos_base do
      ki = FileProxy.create(actor: @hans, title: "Notiz", item_type: :note, content: "")

      assert_difference -> { Task.count }, 1 do
        assert_difference -> { TaskMention.count }, 1 do
          post "/knowledge_items/#{ki.uuid}/task_mentions",
               params: { create_with: "neue Aufgabe aus KI" },
               headers: { "Accept" => "text/vnd.turbo-stream.html" }
        end
      end
      new_task = Task.where(title: "neue Aufgabe aus KI").first
      assert_equal @hans.id, new_task.creator_id
      assert TaskMention.exists?(task: new_task, mentioned_uuid: ki.uuid)
    end
  end

  test "DELETE unlinks task with undo toast" do
    with_isolated_miolimos_base do
      ki   = FileProxy.create(actor: @hans, title: "Notiz", item_type: :note, content: "")
      task = Task.create!(title: "Tu", creator: @hans, assignee: @hans, status: :open)
      TaskMention.create!(task: task, mentioned_uuid: ki.uuid)

      assert_difference -> { TaskMention.count }, -1 do
        delete "/knowledge_items/#{ki.uuid}/task_mentions/#{task.id}",
               headers: { "Accept" => "text/vnd.turbo-stream.html" }
      end
      assert_response :ok
      assert_includes @response.body, "toast_stack"
      assert_includes @response.body, "Tu"
    end
  end
end
