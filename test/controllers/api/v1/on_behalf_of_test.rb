require "test_helper"

# #602 S2: Agent-on-behalf-of — Confused-Deputy-Schutz. Ein Agent, der
# die Anfrage eines Members bearbeitet, hängt ?on_behalf_of=<actor_id>
# an Lese-Aufrufe; die Antwort ist dann auf DESSEN Sichtbarkeit
# gefiltert. Ohne Param: volle Agent-Sicht (Bestand).
class Api::V1::OnBehalfOfTest < ActionDispatch::IntegrationTest
  setup do
    @hans  = create_human(name: "Hans Admin")
    @mia   = create_human(name: "Mia Member", role: :member)
    @agent = AgentActor.create!(name: "obo-#{SecureRandom.hex(3)}", description: "t")
    %w[Task Topic KnowledgeItem Communication Awaiting].each do |rt|
      grant(@agent, rt, %w[read create update delete])
    end
    @headers = { "Authorization" => "Bearer #{@agent.api_token}" }

    @geheim = create_topic(creator: @hans, name: "API Geheim", slug: "api-geheim-#{SecureRandom.hex(3)}")
    @geheim_task = Task.create!(title: "API Geheimtask", creator: @hans,
                                status: :open, skip_default_assignee: true)
    TaskTopic.create!(task: @geheim_task, topic: @geheim, position: 1)
    @geheim_ki = KnowledgeItem.create!(uuid: SecureRandom.uuid, title: "API Geheimdossier",
                                       item_type: :note, file_path: "x/api-geheim.md",
                                       content_hash: "h", body: "geheim", creator: @hans,
                                       published_at: Time.current)
    KnowledgeItemTopic.create!(knowledge_item_uuid: @geheim_ki.uuid, topic: @geheim)

    @mias_task = Task.create!(title: "Mias API-Task", creator: @mia,
                              status: :open, skip_default_assignee: true)
  end

  test "ohne on_behalf_of sieht der Agent alles (Bestand)" do
    get "/api/v1/tasks/#{@geheim_task.id}", headers: @headers
    assert_response :success

    get "/api/v1/topics", headers: @headers
    slugs = JSON.parse(response.body)["data"].map { |t| t["slug"] }
    assert_includes slugs, @geheim.slug
  end

  test "mit on_behalf_of=member ist die Antwort auf dessen Sicht gefiltert" do
    obo = { on_behalf_of: @mia.id }

    get "/api/v1/tasks", params: obo, headers: @headers
    titles = JSON.parse(response.body)["data"].map { |t| t["title"] }
    assert_includes titles, "Mias API-Task"
    refute_includes titles, "API Geheimtask"

    get "/api/v1/tasks/#{@geheim_task.id}", params: obo, headers: @headers
    assert_response :not_found

    get "/api/v1/knowledge_items/#{@geheim_ki.uuid}", params: obo, headers: @headers
    assert_response :not_found

    get "/api/v1/topics", params: obo, headers: @headers
    slugs = JSON.parse(response.body)["data"].map { |t| t["slug"] }
    refute_includes slugs, @geheim.slug

    # Mitgliedschaft öffnet die Sicht.
    TopicMembership.create!(topic: @geheim, actor: @mia, role: :viewer)
    get "/api/v1/tasks/#{@geheim_task.id}", params: obo, headers: @headers
    assert_response :success
  end

  test "unbekannte on_behalf_of-id ist 404, inaktive Nutzer ebenso" do
    get "/api/v1/tasks", params: { on_behalf_of: 999_999 }, headers: @headers
    assert_response :not_found

    @mia.update!(active: false)
    get "/api/v1/tasks", params: { on_behalf_of: @mia.id }, headers: @headers
    assert_response :not_found
  end
end
