require "test_helper"

# #801 P1: Web-Tests für den Task-Reply-Endpoint (#384 Phase 3b) —
# vorher 0 % Abdeckung trotz Live-UI (Task-Diskussionen).
class TaskRepliesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @hans = HumanActor.create!(
      name: "Hans", email: "hans-tr-#{SecureRandom.hex(3)}@t.local",
      password: "secretsecret"
    )
    grant(@hans, "Task", %w[read create update delete])
    # Reply-KIs entstehen via FileProxy.create → braucht KnowledgeItem-Caps.
    grant(@hans, "KnowledgeItem", %w[read create update delete])
    post "/login", params: { email: @hans.email, password: "secretsecret" }

    @task = Task.create!(title: "Diskutier was", creator: @hans, assignee: @hans, status: :open)
  end

  def create_foreign_human
    other = create_human
    grant(other, "KnowledgeItem", %w[read create update])
    other
  end

  def create_reply(body: "ein Beitrag", draft: false, actor: @hans)
    reply = FileProxy.create(actor: actor, title: "Reply-Fixture", item_type: :reply, content: body)
    reply.update!(title: nil, parent_type: "Task", parent_id_int: @task.id,
                  published_at: draft ? nil : Time.current)
    reply
  end

  test "GET index renders the replies list fragment" do
    with_isolated_miolimos_base do
      create_reply(body: "sichtbarer Beitrag")
      get "/tasks/#{@task.id}/replies"
      assert_response :ok
      assert_includes @response.body, "sichtbarer Beitrag"
    end
  end

  test "POST creates published reply threaded to the task and inherits its topics" do
    with_isolated_miolimos_base do
      topic = create_topic(creator: @hans)
      @task.task_topics.create!(topic: topic)

      assert_difference -> { KnowledgeItem.replies.count }, 1 do
        post "/tasks/#{@task.id}/replies",
             params: { body: "Mein Diskussionsbeitrag" },
             headers: { "Accept" => "text/vnd.turbo-stream.html" }
      end
      assert_response :ok
      assert_includes @response.body, "task_replies_#{@task.id}"

      reply = KnowledgeItem.replies.order(:created_at).last
      assert_equal "Task", reply.parent_type
      assert_equal @task.id, reply.parent_id_int
      assert_nil reply.title
      assert reply.published_at.present?, "non-draft reply must be published"
      assert_includes reply.topics.pluck(:slug), topic.slug
    end
  end

  test "POST with draft=true creates unpublished reply" do
    with_isolated_miolimos_base do
      post "/tasks/#{@task.id}/replies",
           params: { body: "Entwurf", draft: "true" },
           headers: { "Accept" => "text/vnd.turbo-stream.html" }
      assert_response :ok
      assert_nil KnowledgeItem.replies.order(:created_at).last.published_at
    end
  end

  test "POST published reply pokes an agent assignee" do
    with_isolated_miolimos_base do
      agent = create_agent
      @task.update!(assignee: agent)
      assert_nil agent.reload.inbox_run_requested_at

      post "/tasks/#{@task.id}/replies",
           params: { body: "bitte übernehmen" },
           headers: { "Accept" => "text/vnd.turbo-stream.html" }
      assert_response :ok
      assert agent.reload.inbox_run_requested_at.present?, "agent assignee must be poked"
    end
  end

  test "POST draft does NOT poke the agent assignee" do
    with_isolated_miolimos_base do
      agent = create_agent
      @task.update!(assignee: agent)

      post "/tasks/#{@task.id}/replies",
           params: { body: "noch nicht fertig", draft: "true" },
           headers: { "Accept" => "text/vnd.turbo-stream.html" }
      assert_response :ok
      assert_nil agent.reload.inbox_run_requested_at, "drafts must not poke"
    end
  end

  test "PATCH updates body of own reply" do
    with_isolated_miolimos_base do
      reply = create_reply(body: "v1")
      patch "/tasks/#{@task.id}/replies/#{reply.uuid}",
            params: { body: "v2" },
            headers: { "Accept" => "text/vnd.turbo-stream.html" }
      assert_response :ok
      assert_equal "v2", reply.reload.body.to_s.strip
    end
  end

  test "PATCH publish=1 publishes a draft and pokes agent assignee" do
    with_isolated_miolimos_base do
      agent = create_agent
      @task.update!(assignee: agent)
      draft = create_reply(body: "Entwurf", draft: true)

      patch "/tasks/#{@task.id}/replies/#{draft.uuid}",
            params: { publish: "1" },
            headers: { "Accept" => "text/vnd.turbo-stream.html" }
      assert_response :ok
      assert draft.reload.published_at.present?
      assert agent.reload.inbox_run_requested_at.present?, "publishing a draft must poke"
    end
  end

  test "PATCH on own reply after foreign follow-up is forbidden (editierbar bis Antwort)" do
    with_isolated_miolimos_base do
      reply = create_reply(body: "meiner")
      other = create_foreign_human
      later = FileProxy.create(actor: other, title: "R2", item_type: :reply, content: "fremde Folge")
      later.update!(title: nil, parent_type: "Task", parent_id_int: @task.id,
                    published_at: Time.current, created_at: reply.created_at + 1.minute)

      patch "/tasks/#{@task.id}/replies/#{reply.uuid}",
            params: { body: "nachträglich" },
            headers: { "Accept" => "text/vnd.turbo-stream.html" }
      assert_response :forbidden
      assert_equal "meiner", reply.reload.body.to_s.strip
    end
  end

  test "DELETE removes own reply even after foreign follow-up (#536)" do
    with_isolated_miolimos_base do
      reply = create_reply(body: "weg damit")
      other = create_foreign_human
      later = FileProxy.create(actor: other, title: "R2", item_type: :reply, content: "Folge")
      later.update!(title: nil, parent_type: "Task", parent_id_int: @task.id,
                    published_at: Time.current, created_at: reply.created_at + 1.minute)

      assert_difference -> { KnowledgeItem.replies.count }, -1 do
        delete "/tasks/#{@task.id}/replies/#{reply.uuid}",
               headers: { "Accept" => "text/vnd.turbo-stream.html" }
      end
      assert_response :ok
    end
  end

  test "DELETE on someone else's reply is forbidden" do
    with_isolated_miolimos_base do
      other = create_foreign_human
      foreign = FileProxy.create(actor: other, title: "F", item_type: :reply, content: "fremd")
      foreign.update!(title: nil, parent_type: "Task", parent_id_int: @task.id,
                      published_at: Time.current)

      delete "/tasks/#{@task.id}/replies/#{foreign.uuid}",
             headers: { "Accept" => "text/vnd.turbo-stream.html" }
      assert_response :forbidden
      assert KnowledgeItem.replies.exists?(uuid: foreign.uuid)
    end
  end

  test "PATCH with unknown reply uuid raises 404" do
    with_isolated_miolimos_base do
      patch "/tasks/#{@task.id}/replies/00000000-0000-0000-0000-000000000000",
            params: { body: "x" }
      assert_response :not_found
    end
  end
end
