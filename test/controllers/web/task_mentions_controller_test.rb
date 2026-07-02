require "test_helper"

class TaskMentionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @hans = HumanActor.create!(
      name: "Hans", email: "hans-tm-#{SecureRandom.hex(3)}@t.local",
      password: "secretsecret"
    )
    grant(@hans, "Task",          %w[read create update])
    grant(@hans, "KnowledgeItem", %w[read create update])
    post "/login", params: { email: @hans.email, password: "secretsecret" }

    @task = Task.create!(title: "Tu was", creator: @hans, assignee: @hans, status: :open)
  end

  test "POST with mentioned_uuid links existing Person-KI to task" do
    with_isolated_miolimos_base do
      person = FileProxy.create(actor: @hans, title: "Max Mustermann",
                                item_type: :person, content: "")
      assert_difference -> { @task.reload.task_mentions.count }, 1 do
        post "/tasks/#{@task.id}/mentions",
             params: { mentioned_uuid: person.uuid },
             headers: { "Accept" => "text/vnd.turbo-stream.html" }
      end
      assert_response :ok
      assert_includes @task.reload.mentioned_kis, person
      assert_includes @response.body, "task_contacts_chips_#{@task.id}"
    end
  end

  test "POST with create_with creates Person-KI and links it" do
    with_isolated_miolimos_base do
      assert_difference -> { KnowledgeItem.persons.count }, 1 do
        assert_difference -> { @task.reload.task_mentions.count }, 1 do
          post "/tasks/#{@task.id}/mentions",
               params: { create_with: "Erika Musterfrau" },
               headers: { "Accept" => "text/vnd.turbo-stream.html" }
        end
      end
      new_person = KnowledgeItem.persons.last
      assert_equal "Erika Musterfrau", new_person.title
      assert_equal "Erika", new_person.first_name
      assert_equal "Musterfrau", new_person.last_name
    end
  end

  test "DELETE unlinks mention with undo toast" do
    with_isolated_miolimos_base do
      person = FileProxy.create(actor: @hans, title: "Max Mustermann",
                                item_type: :person, content: "")
      TaskMention.create!(task: @task, mentioned_uuid: person.uuid)

      assert_difference -> { @task.reload.task_mentions.count }, -1 do
        delete "/tasks/#{@task.id}/mentions/#{person.uuid}",
               headers: { "Accept" => "text/vnd.turbo-stream.html" }
      end
      assert_response :ok
      assert_includes @response.body, "toast_stack"
      assert_includes @response.body, "Max Mustermann"
    end
  end
end
