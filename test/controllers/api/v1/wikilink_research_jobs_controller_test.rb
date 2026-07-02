require "test_helper"

# #203: Coverage fuer den Researcher-Patch-Endpoint (#183).
class Api::V1::WikilinkResearchJobsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @hans = create_human
    grant(@hans, "KnowledgeItem", %w[read create update delete])
    grant(@hans, "Task",          %w[read create update delete])

    # Researcher-Agent als API-Caller — braucht :update auf KnowledgeItem
    # (siehe controller_action_to_capability).
    @researcher = AgentActor.create!(name: "Researcher-#{SecureRandom.hex(2)}",
                                      description: "test", active: true)
    grant(@researcher, "KnowledgeItem", %w[read create update])
    @auth = { "Authorization" => "Bearer #{@researcher.api_token}" }

    # Source-KI (wo der Wikilink steht) + Task (der die Recherche durchfuehrt)
    @source_ki = FileProxy.create(actor: @hans, title: "Quelle mit Wikilink",
                                   item_type: :note, content: "[[Neuer Begriff|https://example.com]]")
    @task = Task.create!(creator: @hans, title: "Recherche: Neuer Begriff",
                         tags: ["wikilink_research"])
    @job = WikilinkResearchJob.create!(source_knowledge_item: @source_ki,
                                        target_title: "Neuer Begriff",
                                        target_source_url: "https://example.com",
                                        task: @task)
  end

  test "PATCH verknuepft target_knowledge_item_id und liefert JSON zurueck" do
    target = FileProxy.create(actor: @hans, title: "Neuer Begriff", item_type: :note, content: "Recherche-Ergebnis")

    patch "/api/v1/wikilink_research_jobs/#{@job.id}",
          params:  { target_knowledge_item_id: target.uuid },
          headers: @auth

    assert_response :success
    body = JSON.parse(@response.body)
    assert_equal @job.id, body["id"]
    assert_equal @source_ki.uuid, body["source_knowledge_item_id"]
    assert_equal "Neuer Begriff", body["target_title"]
    assert_equal "https://example.com", body["target_source_url"]
    assert_equal target.uuid, body["target_knowledge_item_id"]
    assert_equal @task.id, body["task_id"]
    assert_equal target.uuid, @job.reload.target_knowledge_item_id
  end

  test "ohne Authorization-Header schlaegt fehl" do
    patch "/api/v1/wikilink_research_jobs/#{@job.id}",
          params: { target_knowledge_item_id: "any" }
    assert_response :unauthorized
  end

  test "Agent ohne update-Capability auf KnowledgeItem ist gesperrt" do
    no_caps = AgentActor.create!(name: "NoCaps-#{SecureRandom.hex(2)}",
                                  description: "test", active: true)
    patch "/api/v1/wikilink_research_jobs/#{@job.id}",
          params:  { target_knowledge_item_id: "any" },
          headers: { "Authorization" => "Bearer #{no_caps.api_token}" }
    assert_response :forbidden
  end

  test "non-permitted Felder werden ignoriert (Strong Params)" do
    target = FileProxy.create(actor: @hans, title: "Anderer Title", item_type: :note, content: "x")
    patch "/api/v1/wikilink_research_jobs/#{@job.id}",
          params:  { target_title: "Gefakter Titel", target_knowledge_item_id: target.uuid },
          headers: @auth
    assert_response :success
    # target_title bleibt unveraendert, weil nicht im permit-Set
    assert_equal "Neuer Begriff", @job.reload.target_title
    assert_equal target.uuid, @job.target_knowledge_item_id
  end

  test "unbekannte Job-ID liefert 404" do
    patch "/api/v1/wikilink_research_jobs/999999",
          params:  { target_knowledge_item_id: "any" },
          headers: @auth
    assert_response :not_found
  end
end
