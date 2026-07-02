require "test_helper"

class Settings::LlmActivitiesControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @hans = HumanActor.create!(
      name: "Hans", email: "hans-llma-#{SecureRandom.hex(3)}@t.local",
      password: "secretsecret"
    )
    # #564: retry ist eine Mutation (Job einreihen) und braucht seit dem
    # fail-closed-Gated-Default update statt nur read.
    grant(@hans, "Actor", %w[read update])
    post "/login", params: { email: @hans.email, password: "secretsecret" }
  end

  test "GET /settings/llm_activities lists activities filtered by status" do
    LlmActivity.create!(kind: "paragraph_research", actor: @hans,
                        status: "succeeded", input_summary: "ein Absatz")
    LlmActivity.create!(kind: "inbox_ai_transform", actor: @hans,
                        status: "failed", error_message: "boom")

    # #613: Reiter-URL leitet auf den Stack; das Blade zeigt den
    # Default-Ausschnitt (neueste 200, ohne Status-Filter).
    get "/settings/llm_activities"
    follow_redirect!
    assert_response :success
    assert_includes @response.body, "ein Absatz"
    assert_includes @response.body, "succeeded"
    assert_includes @response.body, "failed"
  end

  test "GET /settings/llm_activities/:id shows detail with input/output" do
    a = LlmActivity.create!(
      kind: "paragraph_research", actor: @hans, status: "succeeded",
      input_summary: "Eingabe-Text", output_summary: "Ausgabe-Text"
    )
    get "/settings/llm_activities/#{a.id}"
    follow_redirect!   # #613 St.2: Detail ist ein Blade im Stack
    assert_response :success
    assert_includes @response.body, "Eingabe-Text"
    assert_includes @response.body, "Ausgabe-Text"
  end

  test "POST retry on failed paragraph_research enqueues job and redirects with notice" do
    a = LlmActivity.create!(
      kind: "paragraph_research", actor: @hans, status: "failed",
      source_kind: "knowledge_item", source_id: "ki-uuid#anchor-1",
      error_message: "x"
    )

    assert_enqueued_with(job: ParagraphResearchJob,
                         args: ["ki-uuid", "anchor-1", "", @hans.id]) do
      post "/settings/llm_activities/#{a.id}/retry"
    end
    follow_redirect!   # #613 St.2: direkt zur Stack-URL
    assert_includes @response.body, "Erneut gestartet"
  end

  test "POST retry on activity with unrecoverable source returns alert" do
    a = LlmActivity.create!(
      kind: "paragraph_research", actor: @hans, status: "failed",
      source_kind: "knowledge_item", source_id: "no-anchor",
      error_message: "x"
    )
    assert_no_enqueued_jobs do
      post "/settings/llm_activities/#{a.id}/retry"
    end
    follow_redirect!   # #613 St.2: direkt zur Stack-URL
    assert_includes @response.body, "nicht mehr auffindbar"
  end

  test "actor without Actor read capability gets forbidden" do
    other = HumanActor.create!(
      name: "Other", email: "other-#{SecureRandom.hex(3)}@t.local",
      password: "secretsecret"
    )
    delete "/logout"
    post "/login", params: { email: other.email, password: "secretsecret" }
    get "/settings/llm_activities"
    assert_response :forbidden
  end
end
