require "test_helper"

class ParagraphResearchJobTest < ActiveJob::TestCase
  setup do
    @hans = create_human
    grant(@hans, "KnowledgeItem", %w[read create update delete])
  end

  test "creates a research note linking back to the source paragraph and a succeeded LlmActivity" do
    with_isolated_miolimos_base do
      item = FileProxy.create(
        actor: @hans, title: "Quelle", item_type: :note,
        content: "Ein interessanter Absatz. ^a1\n"
      )

      stub_chat_client(->(**) { "Recherche-Ergebnis." }) do
        ParagraphResearchJob.perform_now(item.uuid, "a1", "Bitte fokussiert", @hans.id)
      end

      research = KnowledgeItem.where.not(uuid: item.uuid).order(:created_at).last
      assert research.title.start_with?("Recherche zu:")
      body = FileProxy.read_body(actor: @hans, knowledge_item: research)
      assert_match "[[#{item.uuid}^a1|↳ Quelle]]", body
      assert_match "Recherche-Ergebnis.",          body

      activity = LlmActivity.last
      assert_equal "succeeded",                  activity.status
      assert_equal "paragraph_research",         activity.kind
      assert_equal "knowledge_item",             activity.source_kind
      assert_equal "#{item.uuid}#a1",            activity.source_id
      assert_equal "knowledge_item",             activity.result_kind
      assert_equal research.uuid,                activity.result_id
    end
  end

  test "no research note is created and activity stays succeeded with empty output when LLM returns blank" do
    with_isolated_miolimos_base do
      item = FileProxy.create(
        actor: @hans, title: "Q", item_type: :note,
        content: "Absatz. ^a1\n"
      )
      assert_no_difference -> { KnowledgeItem.where.not(uuid: item.uuid).count } do
        stub_chat_client(->(**) { "" }) do
          ParagraphResearchJob.perform_now(item.uuid, "a1", "", @hans.id)
        end
      end
      activity = LlmActivity.last
      assert_equal "succeeded", activity.status
      assert_nil activity.result_id
    end
  end

  test "LLM error marks activity as failed and re-raises so Solid Queue retries" do
    with_isolated_miolimos_base do
      item = FileProxy.create(
        actor: @hans, title: "Q", item_type: :note,
        content: "Absatz. ^a1\n"
      )
      raised = false
      stub_chat_client(->(**) { raise Llm::ChatClient::UnavailableError, "kaputt" }) do
        begin
          ParagraphResearchJob.new.perform(item.uuid, "a1", "", @hans.id)
        rescue Llm::ChatClient::UnavailableError
          raised = true
        end
      end
      assert raised, "UnavailableError should propagate so Solid Queue retries"
      activity = LlmActivity.last
      assert_equal "failed", activity.status
      assert_match "kaputt", activity.error_message
    end
  end

  test "returns silently when item or actor is missing" do
    with_isolated_miolimos_base do
      assert_nothing_raised do
        ParagraphResearchJob.perform_now("00000000-0000-0000-0000-000000000000",
                                          "a1", "", @hans.id)
      end
      assert_equal 0, LlmActivity.count
    end
  end

  test "returns silently when anchor not found in item body" do
    with_isolated_miolimos_base do
      item = FileProxy.create(
        actor: @hans, title: "Q", item_type: :note,
        content: "Nichts hat einen Anker.\n"
      )
      assert_nothing_raised do
        ParagraphResearchJob.perform_now(item.uuid, "missing", "", @hans.id)
      end
      assert_equal 0, LlmActivity.count
    end
  end
end
