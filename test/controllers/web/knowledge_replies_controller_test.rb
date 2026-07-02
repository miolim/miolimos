require "test_helper"

# #801 P1: Web-Tests für den KI-Reply-Endpoint (#384 Phase 3a) —
# der API-Zwilling ist getestet, der Web-Pfad war es nicht.
class KnowledgeRepliesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @hans = HumanActor.create!(
      name: "Hans", email: "hans-kr-#{SecureRandom.hex(3)}@t.local",
      password: "secretsecret"
    )
    grant(@hans, "KnowledgeItem", %w[read create update delete])
    post "/login", params: { email: @hans.email, password: "secretsecret" }
  end

  def create_foreign_human
    other = create_human
    grant(other, "KnowledgeItem", %w[read create update])
    other
  end

  def create_parent_ki(actor: @hans)
    FileProxy.create(actor: actor, title: "Parent-#{SecureRandom.hex(3)}",
                     item_type: :note, content: "Basistext")
  end

  def create_reply(parent, body: "ein Beitrag", draft: false, actor: @hans)
    reply = FileProxy.create(actor: actor, title: "Reply-Fixture", item_type: :reply, content: body)
    reply.update!(title: nil, parent_type: "KnowledgeItem", parent_uuid: parent.uuid,
                  published_at: draft ? nil : Time.current)
    reply
  end

  test "GET index renders the replies list fragment" do
    with_isolated_miolimos_base do
      parent = create_parent_ki
      create_reply(parent, body: "sichtbarer Beitrag")
      get "/knowledge_items/#{parent.uuid}/replies"
      assert_response :ok
      assert_includes @response.body, "sichtbarer Beitrag"
    end
  end

  test "POST creates published reply threaded to the KI and inherits its topics" do
    with_isolated_miolimos_base do
      parent = create_parent_ki
      topic  = create_topic(creator: @hans)
      parent.knowledge_item_topics.create!(topic: topic)

      assert_difference -> { KnowledgeItem.replies.count }, 1 do
        post "/knowledge_items/#{parent.uuid}/replies",
             params: { body: "Mein Diskussionsbeitrag" },
             headers: { "Accept" => "text/vnd.turbo-stream.html" }
      end
      assert_response :ok
      assert_includes @response.body, "knowledge_replies_#{parent.uuid}"

      reply = KnowledgeItem.replies.order(:created_at).last
      assert_equal "KnowledgeItem", reply.parent_type
      assert_equal parent.uuid, reply.parent_uuid
      assert reply.published_at.present?
      assert_includes reply.topics.pluck(:slug), topic.slug
    end
  end

  test "POST published reply pokes @-mentioned agents (#518)" do
    with_isolated_miolimos_base do
      parent = create_parent_ki
      agent  = create_agent(name: "poke-target-#{SecureRandom.hex(3)}")

      post "/knowledge_items/#{parent.uuid}/replies",
           params: { body: "Bitte schau mal, @#{agent.name}" },
           headers: { "Accept" => "text/vnd.turbo-stream.html" }
      assert_response :ok
      assert agent.reload.inbox_run_requested_at.present?, "mentioned agent must be poked"
    end
  end

  test "POST draft does NOT poke mentioned agents" do
    with_isolated_miolimos_base do
      parent = create_parent_ki
      agent  = create_agent(name: "draft-target-#{SecureRandom.hex(3)}")

      post "/knowledge_items/#{parent.uuid}/replies",
           params: { body: "Entwurf für @#{agent.name}", draft: "true" },
           headers: { "Accept" => "text/vnd.turbo-stream.html" }
      assert_response :ok
      assert_nil agent.reload.inbox_run_requested_at
    end
  end

  test "PATCH updates body of own reply" do
    with_isolated_miolimos_base do
      parent = create_parent_ki
      reply  = create_reply(parent, body: "v1")
      patch "/knowledge_items/#{parent.uuid}/replies/#{reply.uuid}",
            params: { body: "v2" },
            headers: { "Accept" => "text/vnd.turbo-stream.html" }
      assert_response :ok
      assert_equal "v2", reply.reload.body.to_s.strip
    end
  end

  test "PATCH publish=1 publishes an own draft even after foreign follow-up (#522)" do
    with_isolated_miolimos_base do
      parent = create_parent_ki
      draft  = create_reply(parent, body: "Entwurf", draft: true)
      other  = create_foreign_human
      create_reply(parent, body: "fremde Folge", actor: other)

      patch "/knowledge_items/#{parent.uuid}/replies/#{draft.uuid}",
            params: { publish: "1" },
            headers: { "Accept" => "text/vnd.turbo-stream.html" }
      assert_response :ok
      assert draft.reload.published_at.present?, "own drafts stay publishable (#522)"
    end
  end

  test "PATCH on foreign reply is forbidden" do
    with_isolated_miolimos_base do
      parent  = create_parent_ki
      other   = create_foreign_human
      foreign = create_reply(parent, body: "fremd", actor: other)

      patch "/knowledge_items/#{parent.uuid}/replies/#{foreign.uuid}",
            params: { body: "kapern" },
            headers: { "Accept" => "text/vnd.turbo-stream.html" }
      assert_response :forbidden
      assert_equal "fremd", foreign.reload.body.to_s.strip
    end
  end

  test "DELETE removes own reply" do
    with_isolated_miolimos_base do
      parent = create_parent_ki
      reply  = create_reply(parent, body: "weg damit")
      assert_difference -> { KnowledgeItem.replies.count }, -1 do
        delete "/knowledge_items/#{parent.uuid}/replies/#{reply.uuid}",
               headers: { "Accept" => "text/vnd.turbo-stream.html" }
      end
      assert_response :ok
    end
  end

  test "DELETE on foreign reply is forbidden" do
    with_isolated_miolimos_base do
      parent  = create_parent_ki
      other   = create_foreign_human
      foreign = create_reply(parent, body: "fremd", actor: other)

      delete "/knowledge_items/#{parent.uuid}/replies/#{foreign.uuid}",
             headers: { "Accept" => "text/vnd.turbo-stream.html" }
      assert_response :forbidden
      assert KnowledgeItem.replies.exists?(uuid: foreign.uuid)
    end
  end
end
