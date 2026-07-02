require "test_helper"

class KnowledgeVersionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @hans = HumanActor.create!(
      name: "Hans", email: "hans-kv-#{SecureRandom.hex(3)}@t.local",
      password: "secretsecret"
    )
    grant(@hans, "KnowledgeItem", %w[read create update])
    post "/login", params: { email: @hans.email, password: "secretsecret" }
  end

  test "GET history renders the version drawer with commit list" do
    with_isolated_miolimos_base do
      ki = FileProxy.create(actor: @hans, title: "Hist", item_type: :note, content: "v1")
      FileProxy.update(actor: @hans, knowledge_item: ki, content: "v2")

      get "/knowledge_items/#{ki.uuid}/history"
      assert_response :ok
      assert_includes @response.body, ki.uuid
    end
  end

  test "GET version renders the version preview partial" do
    with_isolated_miolimos_base do |base|
      ki = FileProxy.create(actor: @hans, title: "Ver", item_type: :note, content: "rev1")
      sha = `git -C #{base} rev-parse HEAD`.strip
      FileProxy.update(actor: @hans, knowledge_item: ki, content: "rev2")

      get "/knowledge_items/#{ki.uuid}/version", params: { sha: sha }
      assert_response :ok
    end
  end

  test "POST restore_version writes the historic body back" do
    with_isolated_miolimos_base do |base|
      ki = FileProxy.create(actor: @hans, title: "Roll", item_type: :note, content: "first")
      first_sha = `git -C #{base} rev-parse HEAD`.strip
      FileProxy.update(actor: @hans, knowledge_item: ki, content: "second")

      post "/knowledge_items/#{ki.uuid}/restore_version", params: { sha: first_sha }
      assert_redirected_to "/knowledge_items/#{ki.uuid}"
      assert_equal "first", ki.reload.body
    end
  end

  test "without KnowledgeItem.update capability, restore is forbidden" do
    with_isolated_miolimos_base do |base|
      ki = FileProxy.create(actor: @hans, title: "Read", item_type: :note, content: "x")
      sha = `git -C #{base} rev-parse HEAD`.strip

      read_only = HumanActor.create!(
        name: "Read", email: "ro-#{SecureRandom.hex(3)}@t.local",
        password: "secretsecret"
      )
      grant(read_only, "KnowledgeItem", %w[read])
      post "/login", params: { email: read_only.email, password: "secretsecret" }

      post "/knowledge_items/#{ki.uuid}/restore_version", params: { sha: sha }
      assert_response :forbidden
    end
  end
end
