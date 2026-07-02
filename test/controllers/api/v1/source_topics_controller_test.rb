require "test_helper"

class Api::V1::SourceTopicsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @agent = AgentActor.create!(name: "st-#{SecureRandom.hex(3)}", description: "t")
    grant(@agent, "Source", %w[read create update delete])
    @headers = { "Authorization" => "Bearer #{@agent.api_token}" }

    @source = Source.create!(title: "Schneider 2024", creator: @agent,
                             csl_type: "webpage",
                             slug: "schneider-2024-#{SecureRandom.hex(3)}")
    @topic  = create_topic(creator: @agent, name: "Recherche-X")
  end

  test "POST verknuepft Quelle mit Topic, Default-Relevanz relevant" do
    assert_difference -> { SourceTopic.count }, 1 do
      post "/api/v1/sources/#{@source.slug}/topics",
           params: { topic_id: @topic.id }, headers: @headers
    end
    assert_response :created
    data = JSON.parse(response.body)["data"]
    assert_equal "relevant", data["relevance"]
    assert_equal @topic.slug, data["topic_slug"]
  end

  # #575: Legacy-Wert unreached wird auf die zwei Dimensionen abgebildet
  # (relevant + reached=false) — Alt-Workflows funktionieren weiter.
  test "POST mit legacy relevance unreached + note → relevant, nicht erreicht" do
    post "/api/v1/sources/#{@source.slug}/topics",
         params: { topic_id: @topic.id, relevance: "unreached",
                   note: "Paywall, nicht erreichbar" },
         headers: @headers
    assert_response :created
    st = SourceTopic.last
    assert_equal "relevant", st.relevance
    refute st.reached
    assert_equal "Paywall, nicht erreichbar", st.note
    assert_equal false, JSON.parse(response.body)["data"]["reached"]
  end

  # #575: zwei Dimensionen unabhängig setzen.
  test "PATCH setzt reached unabhängig von der Relevanz" do
    SourceTopic.create!(source: @source, topic: @topic, relevance: "irrelevant")
    patch "/api/v1/sources/#{@source.slug}/topics/#{@topic.id}",
          params: { reached: "0" }, headers: @headers
    assert_response :ok
    st = SourceTopic.find_by(source: @source, topic: @topic)
    assert_equal "irrelevant", st.relevance
    refute st.reached
  end

  test "POST ist idempotent — zweiter Call aktualisiert statt zu duplizieren" do
    post "/api/v1/sources/#{@source.slug}/topics",
         params: { topic_id: @topic.id }, headers: @headers
    assert_no_difference -> { SourceTopic.count } do
      post "/api/v1/sources/#{@source.slug}/topics",
           params: { topic_id: @topic.id, relevance: "irrelevant" }, headers: @headers
    end
    assert_equal "irrelevant", SourceTopic.last.relevance
  end

  test "PATCH aendert die Relevanz" do
    SourceTopic.create!(source: @source, topic: @topic, relevance: "relevant")
    patch "/api/v1/sources/#{@source.slug}/topics/#{@topic.id}",
          params: { relevance: "irrelevant" }, headers: @headers
    assert_response :ok
    assert_equal "irrelevant", SourceTopic.find_by(source: @source, topic: @topic).relevance
  end

  test "POST mit ungueltiger Relevanz → 422" do
    post "/api/v1/sources/#{@source.slug}/topics",
         params: { topic_id: @topic.id, relevance: "vielleicht" }, headers: @headers
    assert_response :unprocessable_entity
  end

  test "DELETE entfernt den Link" do
    SourceTopic.create!(source: @source, topic: @topic)
    assert_difference -> { SourceTopic.count }, -1 do
      delete "/api/v1/sources/#{@source.slug}/topics/#{@topic.id}", headers: @headers
    end
    assert_response :no_content
  end

  test "GET index listet die Topic-Links der Quelle" do
    SourceTopic.create!(source: @source, topic: @topic, relevance: "relevant")
    get "/api/v1/sources/#{@source.slug}/topics", headers: @headers
    assert_response :ok
    data = JSON.parse(response.body)["data"]
    assert_equal 1, data.size
    assert_equal @topic.slug, data.first["topic_slug"]
  end
end
