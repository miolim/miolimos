require "test_helper"

# #203: Coverage fuer den Topic-Picker auf dem Inbox-Detail (#171).
class InboxItemTopicsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @hans = HumanActor.create!(name: "Hans",
                                email: "hans-iit-#{SecureRandom.hex(3)}@t.local",
                                password: "secretsecret")
    grant(@hans, "InboxItem", %w[read update])
    grant(@hans, "Topic",     %w[read])
    post "/login", params: { email: @hans.email, password: "secretsecret" }

    @item  = InboxItem.create!(creator: @hans, source_kind: "web_url",
                                source_url: "https://example.com", status: "pending")
    @topic = Topic.create!(name: "T", slug: "t-#{SecureRandom.hex(3)}", creator: @hans)
  end

  test "POST /inbox/:id/topics verknuepft das Thema" do
    assert_difference -> { InboxItemTopic.count }, 1 do
      post "/inbox/#{@item.id}/topics", params: { topic_id: @topic.id }
    end
    assert_includes @item.reload.topics, @topic
  end

  test "DELETE /inbox/:id/topics/:slug entfernt das Thema" do
    InboxItemTopic.create!(inbox_item: @item, topic: @topic)
    assert_difference -> { InboxItemTopic.count }, -1 do
      delete "/inbox/#{@item.id}/topics/#{@topic.slug}"
    end
    assert_empty @item.reload.topics
  end

  test "Doppeltes POST ist idempotent (kein zweiter Join)" do
    InboxItemTopic.create!(inbox_item: @item, topic: @topic)
    assert_no_difference -> { InboxItemTopic.count } do
      post "/inbox/#{@item.id}/topics", params: { topic_id: @topic.id }
    end
  end
end
