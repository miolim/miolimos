require "test_helper"

# #516 (Hans, 2026-06-05): Identifizieren / Split / Merge der Quelle↔Person-
# Verknüpfung über die API.
class Api::V1::PersonIdentificationTest < ActionDispatch::IntegrationTest
  setup do
    @hans  = create_human
    @agent = AgentActor.create!(name: "a-#{SecureRandom.hex(3)}", description: "t")
    grant(@agent, "Source", %w[read create update delete])
    grant(@agent, "KnowledgeItem", %w[read create update delete])
    @headers = { "Authorization" => "Bearer #{@agent.api_token}" }
  end

  def create_source_with_author(title, name)
    post "/api/v1/sources", params: { title: title, issued_string: "2024", authors: [name] }, headers: @headers
    slug = JSON.parse(response.body)["data"]["slug"]
    [slug, Source.find_by!(slug: slug).source_creators.first]
  end

  test "PATCH creators identifies the link with confidence + via" do
    with_isolated_miolimos_base do
      slug, sc = create_source_with_author("S", "Max Müller")
      assert sc.provisional?
      patch "/api/v1/sources/#{slug}/creators/#{sc.id}",
            params: { identification: "identified", confidence: "bestätigt", identified_via: "orcid" },
            headers: @headers
      assert_response :success
      sc.reload
      assert sc.identified?
      assert_equal "bestätigt", sc.confidence
      assert_equal "orcid", sc.identified_via
      assert sc.identified_by_id.present?
    end
  end

  test "PATCH creators repoints to another person (split)" do
    with_isolated_miolimos_base do
      slug, sc = create_source_with_author("S2", "Max Müller")
      post "/api/v1/knowledge_items", params: { title: "Max Müller (Physiker)", item_type: "person" }, headers: @headers
      new_uuid = JSON.parse(response.body)["data"]["uuid"]
      patch "/api/v1/sources/#{slug}/creators/#{sc.id}", params: { person_uuid: new_uuid }, headers: @headers
      assert_response :success
      assert_equal new_uuid, sc.reload.knowledge_item_uuid
    end
  end

  test "POST merge_into reassigns authorship, supersedes the duplicate, adds alias" do
    with_isolated_miolimos_base do
      slug, sc = create_source_with_author("S3", "Max Müller")
      dup = sc.knowledge_item
      post "/api/v1/knowledge_items", params: { title: "Maximilian Müller", item_type: "person" }, headers: @headers
      target_uuid = JSON.parse(response.body)["data"]["uuid"]

      post "/api/v1/knowledge_items/#{dup.uuid}/merge_into", params: { target_uuid: target_uuid }, headers: @headers
      assert_response :success

      assert_equal 1, SourceCreator.where(knowledge_item_uuid: target_uuid).count
      assert_equal 0, SourceCreator.where(knowledge_item_uuid: dup.uuid).count
      assert_equal target_uuid, dup.reload.superseded_by_uuid
      assert_includes KnowledgeItem.find(target_uuid).aliases.to_a, "Max Müller"
    end
  end

  test "PATCH sets orcid on a person and it round-trips" do
    with_isolated_miolimos_base do
      post "/api/v1/knowledge_items", params: { title: "Eine Person", item_type: "person" }, headers: @headers
      uuid = JSON.parse(response.body)["data"]["uuid"]
      patch "/api/v1/knowledge_items/#{uuid}", params: { orcid: "0000-0002-1825-0097" }, headers: @headers
      assert_response :success
      assert_equal "0000-0002-1825-0097", JSON.parse(response.body)["data"]["orcid"]
      assert_equal "0000-0002-1825-0097", KnowledgeItem.find(uuid).orcid
    end
  end
end
