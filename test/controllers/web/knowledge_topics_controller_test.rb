require "test_helper"

class KnowledgeTopicsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @hans = HumanActor.create!(
      name: "Hans", email: "hans-kt-#{SecureRandom.hex(3)}@t.local",
      password: "secretsecret"
    )
    grant(@hans, "KnowledgeItem", %w[read create update])
    grant(@hans, "Topic",         %w[read create])

    post "/login", params: { email: @hans.email, password: "secretsecret" }

    @item = FileProxy.create(actor: @hans, title: "Notiz",
                             item_type: :note, content: "x",
                             topics: [], contacts: [], tags: [])
  end

  test "POST links existing topic to knowledge item" do
    topic = Topic.create!(name: "Thema", slug: "thema-#{SecureRandom.hex(2)}", creator: @hans)
    assert_difference -> { @item.reload.topics.count }, 1 do
      post "/knowledge_items/#{@item.uuid}/topics",
           params: { topic_id: topic.slug },
           headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end
    assert_response :ok
    assert_includes @item.reload.topics, topic
    assert_includes @response.body, "knowledge_topics_chips_#{@item.uuid}"
  end

  test "POST with create_with creates topic and links it" do
    assert_difference -> { Topic.count }, 1 do
      assert_difference -> { @item.reload.topics.count }, 1 do
        post "/knowledge_items/#{@item.uuid}/topics",
             params: { create_with: "Frisches Thema" },
             headers: { "Accept" => "text/vnd.turbo-stream.html" }
      end
    end
    new_topic = Topic.last
    assert_equal "Frisches Thema", new_topic.name
    assert_equal "frisches-thema", new_topic.slug
    assert_includes @item.reload.topics, new_topic
  end

  test "POST with create_with reuses existing topic by slug" do
    existing = Topic.create!(name: "Vorhanden", slug: "vorhanden", creator: @hans)
    assert_no_difference -> { Topic.count } do
      post "/knowledge_items/#{@item.uuid}/topics",
           params: { create_with: "Vorhanden" },
           headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end
    assert_includes @item.reload.topics, existing
  end

  test "DELETE unlinks topic and emits undo toast" do
    topic = Topic.create!(name: "Bauamt", slug: "t-#{SecureRandom.hex(2)}", creator: @hans)
    KnowledgeItemTopic.create!(knowledge_item: @item, topic: topic)

    assert_difference -> { @item.reload.topics.count }, -1 do
      delete "/knowledge_items/#{@item.uuid}/topics/#{topic.slug}",
             headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end
    assert_response :ok
    # Toast in den Stream
    assert_includes @response.body, "toast_stack"
    assert_includes @response.body, "Bauamt"
    # Undo-URL führt zurück auf den POST mit topic_id=slug
    assert_includes @response.body, %(value="#{topic.slug}")
  end
end
