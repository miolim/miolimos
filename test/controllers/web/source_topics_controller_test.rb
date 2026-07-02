require "test_helper"

# #494 (Hans, 2026-06-03): Web-UI fuer Quelle↔Thema + Relevanz/Notiz.
class SourceTopicsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @hans = create_human
    @hans.update!(password: "secretsecret")
    grant(@hans, "Source", %w[read create update delete])
    grant(@hans, "Topic", %w[read create update delete])
    @source = Source.create!(title: "Müller 2024", slug: "mueller-#{SecureRandom.hex(3)}",
                             csl_type: "webpage", creator: @hans)
    @topic = Topic.create!(name: "Thema #{SecureRandom.hex(3)}", creator: @hans)
    post "/login", params: { email: @hans.email, password: "secretsecret" }
  end

  test "POST weist eine Quelle dem Topic zu (default relevant)" do
    assert_difference -> { SourceTopic.count }, 1 do
      post "/sources/#{@source.slug}/topics",
           params: { topic_id: @topic.id }, as: :turbo_stream
    end
    assert_response :success
    st = SourceTopic.find_by(source: @source, topic: @topic)
    assert_equal "relevant", st.relevance
    assert_match "topic_research_sources_#{@topic.id}", response.body
  end

  test "PATCH aendert die Relevanz" do
    SourceTopic.create!(source: @source, topic: @topic, relevance: "relevant")
    patch "/sources/#{@source.slug}/topics/#{@topic.id}",
          params: { relevance: "irrelevant" }, as: :turbo_stream
    assert_response :success
    assert_equal "irrelevant", SourceTopic.find_by(source: @source, topic: @topic).relevance
  end

  test "PATCH setzt eine Notiz" do
    SourceTopic.create!(source: @source, topic: @topic, relevance: "relevant")
    patch "/sources/#{@source.slug}/topics/#{@topic.id}",
          params: { note: "Kernquelle" }, as: :turbo_stream
    assert_response :success
    assert_equal "Kernquelle", SourceTopic.find_by(source: @source, topic: @topic).note
  end

  test "DELETE entfernt die Zuordnung" do
    SourceTopic.create!(source: @source, topic: @topic, relevance: "relevant")
    assert_difference -> { SourceTopic.count }, -1 do
      delete "/sources/#{@source.slug}/topics/#{@topic.id}", as: :turbo_stream
    end
    assert_response :success
  end

  # #575: zwei Dimensionen — reached unabhängig vom Urteil togglen;
  # die Sektion rendert beide Button-Gruppen.
  test "PATCH toggelt erreicht/nicht-erreicht, Relevanz bleibt" do
    SourceTopic.create!(source: @source, topic: @topic, relevance: "relevant")
    patch "/sources/#{@source.slug}/topics/#{@topic.id}",
          params: { reached: "0" }, as: :turbo_stream
    assert_response :success
    st = SourceTopic.find_by(source: @source, topic: @topic)
    assert_equal "relevant", st.relevance
    refute st.reached
    assert_match "n. erreicht", response.body
  end

  # #577: Recherche-Quellen oeffnen im Stack (blade-link append) und
  # tragen das Plus zum Anhaengen — wie die anderen Listen.
  test "Recherche-Quellen-Eintrag hat blade-link und Plus-Button" do
    SourceTopic.create!(source: @source, topic: @topic, relevance: "relevant")
    get "/topics/#{@topic.slug}/list_card", params: { tab: "sources" }
    assert_response :success
    band = response.body[%r{id="topic_research_sources_#{@topic.id}".*}m]
    assert band, "Recherche-Quellen-Band fehlt"
    assert_includes band, %(data-blade-link-kind-value="source")
    assert_includes band, %(data-blade-link-id-value="#{@source.slug}")
    assert_includes band, "append_to_substack"
  end
end
