require "test_helper"

class TopicsControllerTest < ActionDispatch::IntegrationTest
  include ActionMailer::TestHelper
  setup do
    @hans = HumanActor.create!(
      name: "Hans", email: "hans-tops-#{SecureRandom.hex(3)}@t.local",
      password: "secretsecret"
    )
    grant(@hans, "Topic", %w[read create update delete])
    grant(@hans, "Task", %w[read])
    grant(@hans, "Contact", %w[read])
    grant(@hans, "KnowledgeItem", %w[read])
    grant(@hans, "Communication", %w[read])

    post "/login", params: { email: @hans.email, password: "secretsecret" }
  end

  def create_topic(name: "Topic", template: false)
    Topic.create!(name: name, slug: name.parameterize + "-#{SecureRandom.hex(2)}", creator: @hans, template: template)
  end

  # #456 (Hans, 2026-06-02): /topics ist jetzt eine Blade-Stack-Seite mit
  # der Themen-Liste als Starter (eigener Pfad/History).
  test "GET /topics rendert die Themen-Liste als Blade-Stack-Starter" do
    create_topic(name: "Test-Thema")
    get "/topics"
    assert_response :success
    assert_includes @response.body, "Test-Thema"
    assert_match %r{data-uuid="list:topics"}, @response.body
    assert_match %r{data-blade-stack-history-storage-key-value="topics.stack.history"}, @response.body
  end

  test "GET /topics/:slug with tasks tab" do
    topic = create_topic(name: "MyTopic")
    task  = Task.create!(title: "Eine Aufgabe", creator: @hans, status: :open)
    TaskTopic.create!(task: task, topic: topic, position: 1)

    get "/topics/#{topic.slug}"
    assert_response :success
    assert_includes @response.body, "MyTopic"
    assert_includes @response.body, "Eine Aufgabe"
  end

  test "GET /topics/:slug with unknown slug → 404" do
    get "/topics/does-not-exist"
    assert_response :not_found
  end

  test "POST /topics creates a new topic with current_actor as creator" do
    assert_difference -> { Topic.count }, 1 do
      post "/topics", params: { topic: { name: "Neues", slug: "neues-#{SecureRandom.hex(2)}" } }
    end
    assert_equal @hans.id, Topic.order(:id).last.creator_id
  end

  test "POST /topics/:slug/instantiate on template" do
    template = create_topic(name: "Tmpl", template: true)
    Task.create!(title: "Aus Vorlage", creator: @hans).tap do |t|
      TaskTopic.create!(task: t, topic: template, position: 1)
    end

    post instantiate_topic_path(template.slug), params: { new_name: "Kunde A" }

    assert_response :redirect
    new_topic = Topic.find_by(name: "Kunde A")
    refute_nil new_topic
    refute new_topic.template?
  end

  test "instantiate on non-template redirects with alert" do
    regular = create_topic(name: "Normal")
    post instantiate_topic_path(regular.slug), params: { new_name: "x" }
    follow_redirect!
    assert_response :success
  end

  # #163 Phase 4: Blade-Card-Fragment fuer Cross-Entity-Stack — eine
  # schlanke Glance-Card, gerendert ohne Layout, mit stable data-uuid.
  test "GET /topics/:slug/card liefert das Reiter-Blade (#571: kein Legacy-Detail mehr)" do
    topic = create_topic(name: "Blade-Topic")
    get card_topic_path(topic.slug)
    assert_response :success
    # topic: ist jetzt Alias auf das Reiter-Blade (list:topic:).
    assert_match %r{data-uuid="list:topic:#{topic.slug}"}, @response.body
    assert_includes @response.body, "Blade-Topic"
    refute_match %r{<html}, @response.body
  end

  # #247: Listen-Blade fuer Topic — Aufgaben-Liste mit stable
  # data-uuid="list:topic:<slug>". Initial schlug das fehl, weil
  # set_topic-before_action :list_card nicht im only-Filter hatte.
  test "GET /topics/:slug/list_card renders list blade card fragment" do
    topic = create_topic(name: "Listen-Topic")
    get list_card_topic_path(topic.slug)
    assert_response :success
    assert_match %r{data-uuid="list:topic:#{topic.slug}"}, @response.body
    assert_includes @response.body, "Listen-Topic"
    refute_match %r{<html}, @response.body
  end

  # #472 (Hans, 2026-06-02): create_synthesis + research_kind/-question
  # entfernt — Synthesen entstehen jetzt ueber die Synthese-KI-Vorlagen.
  # Zugehoerige Tests geloescht.

  # #253: Subtopics-Tab listet die Sub-Themen hierarchisch; Klick
  # appended deren List-View (kind: topic_list).
  # #533 1d: Zeiten-Reiter eines Projekts.
  test "GET /topics/:slug/list_card?tab=times rendert den Zeiten-Reiter" do
    topic = create_topic(name: "Projekt Z")
    get list_card_topic_path(topic.slug, tab: "times")
    assert_response :success
    assert_includes @response.body, "Zeiten"
  end

  test "GET /topics/:slug/list_card?tab=subtopics renders subtopic tree" do
    parent = create_topic(name: "Eltern-Topic")
    child  = create_topic(name: "Kind-Topic")
    child.update!(parent_topic_id: parent.id)

    get list_card_topic_path(parent.slug, tab: "subtopics")
    assert_response :success
    assert_includes @response.body, "Kind-Topic"
    assert_match %r{data-blade-link-kind-value="topic_list"}, @response.body
    assert_match %r{data-blade-link-id-value="#{child.slug}"}, @response.body
  end

  # #464 (Hans, 2026-06-02): Das Themen-Listen-Blade (/topics/list_card)
  # zeigt Sub-Topics jetzt hierarchisch — vorher nur Top-Level.
  test "GET /topics/list_card zeigt Sub-Topics hierarchisch" do
    parent = create_topic(name: "Eltern-Liste-XZ")
    child  = create_topic(name: "Kind-Liste-XZ")
    child.update!(parent_topic_id: parent.id)

    get "/topics/list_card"
    assert_response :success
    assert_includes @response.body, "Eltern-Liste-XZ"
    assert_includes @response.body, "Kind-Liste-XZ"
    assert_match %r{data-blade-link-id-value="#{child.slug}"}, @response.body
  end
  # ── #566/#567: Eigenschaften-Blade + Kunde-Zuordnung ──────────────────────
  test "properties_card rendert das Eigenschaften-Blade mit Kunde-Picker" do
    topic = Topic.create!(name: "Props-Probe", slug: "props-#{SecureRandom.hex(3)}", creator: @hans)
    get "/topics/#{topic.slug}/properties_card"
    assert_response :success
    assert_includes @response.body, "stack_card_topicprops:#{topic.slug}"
    assert_includes @response.body, "Eigenschaften · Props-Probe"
    # Kunde-Picker zielt auf set_customer und schlägt Personen/Orgs per UUID vor.
    assert_includes @response.body, "/topics/#{topic.slug}/set_customer"
    assert_includes @response.body, "id_as_uuid=1"
    # Topic-Form (eine Quelle mit der Edit-Seite) ist eingebettet.
    assert_includes @response.body, "topic[name]"
  end

  test "set_customer ordnet zu, macht zum Projekt und löst wieder" do
    topic = Topic.create!(name: "Kunde-Probe", slug: "kd-#{SecureRandom.hex(3)}", creator: @hans)
    kunde = KnowledgeItem.create!(uuid: SecureRandom.uuid, title: "Kunde GmbH",
                                  item_type: :organization, creator: @hans,
                                  file_path: "x/kunde.md", content_hash: "h", body: "")

    post "/topics/#{topic.slug}/set_customer", params: { value: kunde.uuid },
         headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_response :success
    assert_equal kunde.uuid, topic.reload.customer_uuid
    assert topic.project?
    # #571: Antwort ersetzt das ganze Eigenschaften-Blade (Chip + Portal-
    # Sektion leben dort und sind im frischen Render enthalten).
    assert_match %r{<turbo-stream action="replace" target="stack_card_topicprops:#{topic.slug}"}, @response.body
    assert_includes @response.body, "topic_customer_chip_#{topic.id}"
    assert_includes @response.body, "Kundenportal"

    post "/topics/#{topic.slug}/set_customer", params: { value: "" },
         headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_nil topic.reload.customer_uuid
    refute topic.project?
  end

  test "Pencil im Topic-Blade appendet das Eigenschaften-Blade (kein Voll-Nav)" do
    topic = Topic.create!(name: "Pencil-Probe", slug: "pp-#{SecureRandom.hex(3)}", creator: @hans)
    get "/topics/#{topic.slug}/card"
    assert_response :success
    assert_includes @response.body, 'data-blade-link-kind-value="topic_props"'
    refute_match %r{href="/topics/#{topic.slug}/edit"}, @response.body
  end
  # ── #570: Zugang anlegen ≠ Link senden (entkoppelt) ───────────────────────
  test "Portal-Zugang anlegen mailt NICHT; Link senden mailt genau einmal" do
    topic = Topic.create!(name: "Entkoppel-Probe", slug: "ek-#{SecureRandom.hex(3)}", creator: @hans)

    assert_enqueued_emails 0 do
      post "/topics/#{topic.slug}/portal_accesses", params: { email: "kunde@example.com" },
           headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end
    access = PortalAccess.find_by!(topic: topic, email: "kunde@example.com")
    assert_includes @response.body, "Link senden"

    assert_enqueued_emails 1 do
      post "/portal_accesses/#{access.id}/send_link",
           headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end
    assert_includes @response.body, "verschickt"
  end
  # ── #571: Direkt ins Portal (Kundensicht) ─────────────────────────────────
  test "portal_preview leitet mit gültigem Magic-Token ins Portal; ohne Zugang Alert" do
    kunde = KnowledgeItem.create!(uuid: SecureRandom.uuid, title: "PV-Kunde",
                                  item_type: :organization, creator: @hans,
                                  file_path: "x/pv.md", content_hash: "h", body: "")
    topic = Topic.create!(name: "Preview-Probe", slug: "pv-#{SecureRandom.hex(3)}",
                          creator: @hans, customer_uuid: kunde.uuid)

    # ohne Zugang → zurück mit Hinweis
    get "/topics/#{topic.slug}/portal_preview"
    assert_response :redirect
    assert_match(/Kein aktiver Portal-Zugang/, flash[:alert].to_s)

    access = PortalAccess.create!(topic: topic, email: "pv@example.com")
    get "/topics/#{topic.slug}/portal_preview"
    assert_response :redirect
    url = @response.redirect_url
    assert_includes url, "/portal/session/"
    token = url.split("/portal/session/").last
    assert_equal access.id, PortalAccess.from_magic_token(token)&.id,
      "der Token im Redirect muss ein gültiger Magic-Token des Zugangs sein"

    # Icon erscheint im Blade nur bei Projekten
    get "/topics/#{topic.slug}/card"
    assert_includes @response.body, "portal_preview"
    plain = Topic.create!(name: "Ohne-Kunde", slug: "ok-#{SecureRandom.hex(3)}", creator: @hans)
    get "/topics/#{plain.slug}/card"
    refute_includes @response.body, "portal_preview"
  end
end
