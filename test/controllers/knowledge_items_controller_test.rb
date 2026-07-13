require "test_helper"

# #982: Der Browser-Tab-Titel der KI-Stack-Seite folgt dem Einstieg —
# Personen-Liste und Person/Org-Details hießen vorher pauschal „Wissen".
class KnowledgeItemsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @hans = HumanActor.create!(
      name: "Hans", email: "hans-ki-index-#{SecureRandom.hex(3)}@t.local",
      password: "secretsecret"
    )
    grant(@hans, "KnowledgeItem", %w[read create update delete])
    post "/login", params: { email: @hans.email, password: "secretsecret" }
  end

  test "index betitelt den Tab mit Wissen" do
    with_isolated_miolimos_base do
      get "/knowledge_items"
      assert_response :success
      assert_select "title", text: /\AWissen – miolimOS\z/
    end
  end

  test "Personen-Listen-Stack betitelt den Tab mit Kontakte" do
    with_isolated_miolimos_base do
      get "/knowledge_items", params: { stack: "list:persons" }
      assert_response :success
      assert_select "title", text: /\AKontakte – miolimOS\z/
    end
  end

  test "item_type-Filter person (alter /contacts-Redirect) betitelt den Tab mit Kontakte" do
    with_isolated_miolimos_base do
      get "/knowledge_items", params: { item_type: "person" }
      assert_response :success
      assert_select "title", text: /\AKontakte – miolimOS\z/
    end
  end

  test "Person als erste Stack-Card betitelt den Tab mit ihrem Namen" do
    with_isolated_miolimos_base do
      person = FileProxy.create(actor: @hans, title: "Anna Bauer", item_type: :person, content: "")
      get "/knowledge_items", params: { stack: person.uuid }
      assert_response :success
      assert_select "title", text: /\AAnna Bauer – miolimOS\z/
    end
  end

  test "Nicht-Personen-KI als Stack bleibt bei Wissen" do
    with_isolated_miolimos_base do
      note = FileProxy.create(actor: @hans, title: "Notiz X", item_type: :note, content: "Inhalt")
      get "/knowledge_items", params: { stack: note.uuid }
      assert_response :success
      assert_select "title", text: /\AWissen – miolimOS\z/
    end
  end
end
