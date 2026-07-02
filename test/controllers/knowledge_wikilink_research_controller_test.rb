require "test_helper"

# #378 Phase 4 (Hans, 2026-05-26): Tests fuer den ausgelagerten
# KnowledgeWikilinkResearchController. URLs bleiben unter
# /knowledge_items/:uuid/{request_entity_import,start_wikilink_research}.
class KnowledgeWikilinkResearchControllerTest < ActionDispatch::IntegrationTest
  setup do
    @hans = HumanActor.create!(
      name: "Hans",
      email: "hans-research-#{SecureRandom.hex(3)}@t.local",
      password: "secretsecret"
    )
    grant(@hans, "KnowledgeItem", %w[read create update delete])
    grant(@hans, "Task",          %w[read create update delete])
    @researcher = AgentActor.find_by(email: "miolim_researcher@miolim.de") ||
                  AgentActor.create!(name: "Researcher",
                                     email: "miolim_researcher@miolim.de",
                                     description: "Researcher for tests")
    post "/login", params: { email: @hans.email, password: "secretsecret" }
  end

  def create_note(content)
    FileProxy.create(actor: @hans, title: "Quelle", item_type: :note, content: content)
  end

  test "POST request_entity_import creates ONE task for missing entities" do
    with_isolated_miolimos_base do
      body = "[[Foo Bar|https://example.com/foo]] und [[Baz|https://example.com/baz]]\n"
      item = create_note(body)
      assert_difference -> { Task.where(assignee_id: @researcher.id).count }, 1 do
        post "/knowledge_items/#{item.uuid}/request_entity_import",
             params: {}, as: :json
      end
      assert_response :success
      json = JSON.parse(response.body)
      assert_equal 2, json["count"]
      assert json["task_id"].present?
    end
  end

  test "POST request_entity_import returns count=0 when no entities" do
    with_isolated_miolimos_base do
      item = create_note("Plain note without wikilinks.\n")
      assert_no_difference -> { Task.count } do
        post "/knowledge_items/#{item.uuid}/request_entity_import",
             params: {}, as: :json
      end
      assert_response :success
      json = JSON.parse(response.body)
      assert_equal 0, json["count"]
    end
  end

  test "POST start_wikilink_research creates Task + Job" do
    with_isolated_miolimos_base do
      item = create_note("text\n")
      assert_difference -> { WikilinkResearchJob.count }, 1 do
        post "/knowledge_items/#{item.uuid}/start_wikilink_research",
             params: { title: "Neue Person", source_url: "https://x.org/p" },
             as: :json
      end
      assert_response :success
      json = JSON.parse(response.body)
      assert_equal "started", json["state"]
      assert json["job_id"].present?
    end
  end

  # #672: Auftragstext kommt aus der (editierbaren) Vorlage; Platzhalter
  # werden gefüllt, das missverständliche „Knowledge-Item-Karte" ist weg.
  test "start_wikilink_research nutzt die Vorlage + füllt Platzhalter" do
    with_isolated_miolimos_base do
      item = create_note("text\n")
      post "/knowledge_items/#{item.uuid}/start_wikilink_research",
           params: { title: "Audrey Tang", source_url: "https://x.org/v" }, as: :json
      task = Task.order(:id).last
      assert_includes task.description, "Audrey Tang"
      assert_includes task.description, "https://x.org/v"
      assert_includes task.description, "Verfahren: Entitäts-Recherche"
      refute_includes task.description, "Knowledge-Item-Karte"
      assert_includes task.description, "Job-ID:"   # mechanische Zeile angehängt
    end
  end

  test "start_wikilink_research respektiert eine editierte Vorlage" do
    with_isolated_miolimos_base do
      Setting.set("wikilink_research_prompt", "FIX: Lege {{title}} an. Quelle {{url}}.")
      item = create_note("text\n")
      post "/knowledge_items/#{item.uuid}/start_wikilink_research",
           params: { title: "Max", source_url: "https://y.org" }, as: :json
      task = Task.order(:id).last
      assert_includes task.description, "FIX: Lege Max an. Quelle https://y.org."
    end
  ensure
    Setting.where(key: "wikilink_research_prompt").destroy_all
  end

  test "POST start_wikilink_research is idempotent for same title" do
    with_isolated_miolimos_base do
      item = create_note("text\n")
      post "/knowledge_items/#{item.uuid}/start_wikilink_research",
           params: { title: "Doppel", source_url: "https://x.org/d" },
           as: :json
      assert_response :success
      first = JSON.parse(response.body)

      assert_no_difference -> { WikilinkResearchJob.count } do
        post "/knowledge_items/#{item.uuid}/start_wikilink_research",
             params: { title: "Doppel", source_url: "https://x.org/d" },
             as: :json
      end
      assert_response :success
      second = JSON.parse(response.body)
      assert_equal "already_running", second["state"]
      assert_equal first["task_id"], second["task_id"]
    end
  end

  test "POST start_wikilink_research returns 422 when title or url missing" do
    with_isolated_miolimos_base do
      item = create_note("text\n")
      post "/knowledge_items/#{item.uuid}/start_wikilink_research",
           params: { title: "", source_url: "https://x.org/d" },
           as: :json
      assert_response :unprocessable_entity
    end
  end
end
