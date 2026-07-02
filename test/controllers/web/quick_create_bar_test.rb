require "test_helper"

# #641: Quick-Add-Aufgabe in der Topbar — vier Tier-Presets
# (Topic+Zugewiesen) + Vorlagenliste unter den Feldern.
class QuickCreateBarTest < ActionDispatch::IntegrationTest
  setup do
    @hans = create_human(password: "secretsecret")
    %w[Task Topic Actor KnowledgeItem].each { |rt| grant(@hans, rt, %w[read create update]) }
    post "/login", params: { email: @hans.email, password: "secretsecret" }
  end

  test "Topbar-Quick-Add zeigt die vier Preset-Icons" do
    get "/tasks"
    assert_response :success
    %w[cat squirrel bird fish].each do |p|
      assert_includes @response.body, %(data-preset="#{p}"), "Preset #{p} fehlt"
    end
    assert_includes @response.body, "task-quickadd-prefs#selectPreset"
  end

  test "Vorlagenliste liegt im Fluss unter den Feldern (kein absolute-Overlay)" do
    get "/tasks"
    list = @response.body[/<ul data-task-template-picker-target="list"[^>]*class="([^"]*)"/, 1]
    refute_nil list
    refute_includes list, "absolute"
    assert_includes list, "mt-2"
  end
end
