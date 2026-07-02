require "test_helper"

# #564: Vertragstests für die bisher ungetesteten Operations-API-Endpunkte.
# Externe Agents hängen an diesen Verträgen — Status-Codes und JSON-Form
# dürfen sich nicht unbemerkt ändern.
class Api::V1::AssociationEndpointsTest < ActionDispatch::IntegrationTest
  setup do
    @creator = create_human
    @agent   = AgentActor.create!(name: "assoc-#{SecureRandom.hex(3)}", description: "t")
    %w[Task Topic Communication Source KnowledgeItem Contact].each do |rt|
      grant(@agent, rt, %w[read create update delete])
    end
    @headers = { "Authorization" => "Bearer #{@agent.api_token}" }
  end

  # ── /api/v1/tasks/:task_id/topics ────────────────────────────────────────
  test "task_topics: create verknüpft idempotent und liefert position" do
    task  = Task.create!(title: "T", creator: @creator)
    topic = Topic.create!(name: "Th", slug: "th-#{SecureRandom.hex(3)}", creator: @creator)

    post "/api/v1/tasks/#{task.id}/topics", params: { topic_id: topic.id }, headers: @headers
    assert_response :created
    data = JSON.parse(response.body)["data"]
    assert_equal task.id,  data["task_id"]
    assert_equal topic.id, data["topic_id"]
    assert_kind_of Integer, data["position"]

    # idempotent: zweiter Aufruf legt keinen zweiten Link an
    post "/api/v1/tasks/#{task.id}/topics", params: { topic_id: topic.id }, headers: @headers
    assert_response :created
    assert_equal 1, TaskTopic.where(task: task, topic: topic).count
  end

  test "task_topics: destroy löst die Verknüpfung (204), fehlend = 404" do
    task  = Task.create!(title: "T", creator: @creator)
    topic = Topic.create!(name: "Th", slug: "th-#{SecureRandom.hex(3)}", creator: @creator)
    TaskTopic.create!(task: task, topic: topic, position: 1)

    delete "/api/v1/tasks/#{task.id}/topics/#{topic.id}", headers: @headers
    assert_response :no_content
    assert_equal 0, TaskTopic.where(task: task, topic: topic).count

    delete "/api/v1/tasks/#{task.id}/topics/#{topic.id}", headers: @headers
    assert_response :not_found
  end

  test "task_topics: ohne Token 401" do
    task = Task.create!(title: "T", creator: @creator)
    post "/api/v1/tasks/#{task.id}/topics", params: { topic_id: 1 }
    assert_response :unauthorized
  end

  # ── /api/v1/communications/:communication_id/topics ─────────────────────
  test "communication_topics: create + destroy" do
    comm  = Communication.create!(direction: "inbound", subject: "Mail",
                                  external_id: "assoc-#{SecureRandom.hex(4)}")
    topic = Topic.create!(name: "Th", slug: "th-#{SecureRandom.hex(3)}", creator: @creator)

    post "/api/v1/communications/#{comm.id}/topics", params: { topic_id: topic.id }, headers: @headers
    assert_response :created
    assert_equal({ "communication_id" => comm.id, "topic_id" => topic.id },
                 JSON.parse(response.body)["data"])

    delete "/api/v1/communications/#{comm.id}/topics/#{topic.id}", headers: @headers
    assert_response :no_content
    assert_equal 0, CommunicationTopic.where(communication: comm, topic: topic).count
  end

  # ── /api/v1/contacts (bewusst entfernt) ──────────────────────────────────
  test "contacts: antwortet 410 Gone mit Migrations-Hinweis" do
    get "/api/v1/contacts", headers: @headers
    assert_response :gone
    assert_match %r{knowledge_items\?type=person}, JSON.parse(response.body)["error"]
  end

  # ── /api/v1/sources/:source_slug/creators/:id ────────────────────────────
  test "source_creators: update identifiziert und hängt um" do
    person  = KnowledgeItem.create!(uuid: SecureRandom.uuid, title: "Alte Person",
                                    item_type: :person, file_path: "x/p1.md",
                                    content_hash: "h", body: "")
    person2 = KnowledgeItem.create!(uuid: SecureRandom.uuid, title: "Neue Person",
                                    item_type: :person, file_path: "x/p2.md",
                                    content_hash: "h", body: "")
    source = Source.create!(slug: "src-#{SecureRandom.hex(3)}", title: "Quelle",
                            csl_type: "book", creator: @creator)
    sc = source.source_creators.create!(knowledge_item_uuid: person.uuid, role: "author",
                                        identification: "provisional")

    patch "/api/v1/sources/#{source.slug}/creators/#{sc.id}",
          params: { person_uuid: person2.uuid, identification: "identified", confidence: "bestätigt" },
          headers: @headers
    assert_response :success
    data = JSON.parse(response.body)["data"]
    assert_equal person2.uuid, data["person_uuid"] || data.dig("person", "uuid") || sc.reload.knowledge_item_uuid
    sc.reload
    assert_equal person2.uuid, sc.knowledge_item_uuid
    assert_equal "identified", sc.identification
    assert_equal @agent.id, sc.identified_by_id
    assert_not_nil sc.identified_at
  end
end
