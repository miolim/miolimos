require "test_helper"

class KnowledgeMentionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @hans = HumanActor.create!(
      name: "Hans", email: "hans-km-#{SecureRandom.hex(3)}@t.local",
      password: "secretsecret"
    )
    grant(@hans, "KnowledgeItem", %w[read create update delete])
    post "/login", params: { email: @hans.email, password: "secretsecret" }
  end

  def with_isolated_miolimos_base(&block)
    super(&block)
  end

  test "POST with create_with creates Person-KI and links it" do
    with_isolated_miolimos_base do
      item = FileProxy.create(actor: @hans, title: "Notiz", item_type: :note,
                              content: "x")
      assert_difference -> { KnowledgeItem.persons.count }, 1 do
        assert_difference -> { item.reload.knowledge_item_mentions.count }, 1 do
          post "/knowledge_items/#{item.uuid}/mentions",
               params: { create_with: "Erika Musterfrau" },
               headers: { "Accept" => "text/vnd.turbo-stream.html" }
        end
      end
      assert_response :ok
      new_person = KnowledgeItem.persons.last
      assert_equal "Erika Musterfrau", new_person.title
      assert_equal "Erika", new_person.first_name
      assert_equal "Musterfrau", new_person.last_name
      assert_includes item.reload.mentioned_kis, new_person
    end
  end

  test "POST with mentioned_uuid links existing Person-KI" do
    with_isolated_miolimos_base do
      item   = FileProxy.create(actor: @hans, title: "Notiz", item_type: :note,
                                content: "x")
      person = FileProxy.create(actor: @hans, title: "Max Mustermann",
                                item_type: :person, content: "")
      assert_difference -> { item.reload.knowledge_item_mentions.count }, 1 do
        post "/knowledge_items/#{item.uuid}/mentions",
             params: { mentioned_uuid: person.uuid },
             headers: { "Accept" => "text/vnd.turbo-stream.html" }
      end
      assert_includes item.reload.mentioned_kis, person
    end
  end

  test "POST refuses self-mention" do
    with_isolated_miolimos_base do
      person = FileProxy.create(actor: @hans, title: "Max Mustermann",
                                item_type: :person, content: "")
      assert_no_difference -> { person.reload.knowledge_item_mentions.count } do
        post "/knowledge_items/#{person.uuid}/mentions",
             params: { mentioned_uuid: person.uuid },
             headers: { "Accept" => "text/vnd.turbo-stream.html" }
      end
    end
  end

  test "DELETE unlinks mention and emits undo toast" do
    with_isolated_miolimos_base do
      item   = FileProxy.create(actor: @hans, title: "Notiz", item_type: :note,
                                content: "x")
      person = FileProxy.create(actor: @hans, title: "Max Mustermann",
                                item_type: :person, content: "")
      KnowledgeItemMention.create!(knowledge_item: item, mentioned_uuid: person.uuid)

      assert_difference -> { item.reload.knowledge_item_mentions.count }, -1 do
        delete "/knowledge_items/#{item.uuid}/mentions/#{person.uuid}",
               headers: { "Accept" => "text/vnd.turbo-stream.html" }
      end
      assert_response :ok
      assert_includes @response.body, "toast_stack"
      assert_includes @response.body, "Max Mustermann"
    end
  end
end
