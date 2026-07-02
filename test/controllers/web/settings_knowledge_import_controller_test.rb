require "test_helper"

# #203: Coverage fuer den Knowledge-Import-Settings-Tab.
class SettingsKnowledgeImportControllerTest < ActionDispatch::IntegrationTest
  setup do
    @hans = HumanActor.create!(name: "Hans",
                                email: "hans-ski-#{SecureRandom.hex(3)}@t.local",
                                password: "secretsecret")
    grant(@hans, "KnowledgeItem", %w[read create update delete])
    grant(@hans, "Actor", %w[read])   # #613: Settings-Stack-Gate
    post "/login", params: { email: @hans.email, password: "secretsecret" }
  end

  test "GET /settings/knowledge_import zeigt Default-Prompt" do
    get "/settings/knowledge_import"
    follow_redirect!   # #613
    assert_response :success
    # Mind. der Inbox-Pfad-Hinweis ist da
    assert_includes @response.body, "Inbox"
  end

  test "PATCH update_prompt speichert custom Prompt und zeigt ihn an" do
    patch "/settings/knowledge_import_prompt", params: { prompt: "Mein eigener Prompt." }
    assert_redirected_to settings_knowledge_import_path
    assert_equal "Mein eigener Prompt.", Setting.get("chat_import_prompt")

    get "/settings/knowledge_import"
    follow_redirect!   # #613
    assert_includes @response.body, "Mein eigener Prompt."
  end

  test "POST reset_prompt entfernt den custom Prompt" do
    Setting.set("chat_import_prompt", "Custom-Override")
    post "/settings/knowledge_import_prompt_reset"
    assert_redirected_to settings_knowledge_import_path
    assert_nil Setting.where(key: "chat_import_prompt").first
  end

  # #672: editierbare Wikilink-Recherche-Vorlage.
  test "PATCH/Reset research_prompt speichert und entfernt die Vorlage" do
    patch "/settings/research_prompt", params: { prompt: "Eigene Vorlage {{title}}." }
    assert_redirected_to settings_knowledge_import_path
    assert_equal "Eigene Vorlage {{title}}.", Setting.get("wikilink_research_prompt")

    post "/settings/research_prompt_reset"
    assert_nil Setting.where(key: "wikilink_research_prompt").first
  end

  test "POST run_import bei leerer Inbox: Notice ohne Errors" do
    with_isolated_miolimos_base do |base|
      # Inbox-Path ueberschreiben auf temporaeren Ordner (leer)
      empty_inbox = base.join("inbox-empty")
      FileUtils.mkdir_p(empty_inbox)
      ENV["MIOLIMOS_INBOX_PATH"] = empty_inbox.to_s
      # WikiImporter::INBOX_PATH ist eine Konstante; wir koennen sie zur
      # Test-Zeit zwar nicht neu setzen, aber der Import laeuft sowieso
      # leer durch, wenn das default-Verzeichnis nicht existiert.
      post "/settings/knowledge_import_run"
      assert_redirected_to settings_knowledge_import_path
      follow_redirect!
      assert_match(/leer|nichts zu importieren/i, flash[:notice].to_s)
    end
  ensure
    ENV.delete("MIOLIMOS_INBOX_PATH")
  end

  test "Agent ohne Capability sieht 403" do
    delete "/logout"
    no_caps = HumanActor.create!(name: "NoCaps",
                                  email: "nocaps-#{SecureRandom.hex(2)}@t.local",
                                  password: "secretsecret")
    post "/login", params: { email: no_caps.email, password: "secretsecret" }
    get "/settings/knowledge_import"
    assert_response :forbidden
  end
end
