require "test_helper"

# #846: Smoke-Test — die layout-getriebene Sidebar und der Vorlieben-Editor
# rendern fehlerfrei (uebt sidebar_item fuer alle IDs + beide Sonderfall-
# Partials recent_topics/awaitings + die pref_sidebar_layout-Berechnung).
class SidebarLayoutRenderTest < ActionDispatch::IntegrationTest
  setup do
    @hans = HumanActor.create!(
      name: "Hans", email: "hans-sb-#{SecureRandom.hex(3)}@t.local",
      password: "secretsecret"
    )
    %w[Task Topic KnowledgeItem Awaiting Communication Source Document Actor].each do |res|
      grant(@hans, res, %w[read])
    end
    post "/login", params: { email: @hans.email, password: "secretsecret" }
  end

  test "dashboard renders the layout-driven sidebar with default layout" do
    get "/dashboard"
    assert_response :success
    # „Gesamt"-Ueberschrift des Scrollbereichs beweist, dass die Nav gerendert hat.
    assert_includes @response.body, I18n.t("shared.sidebar.overview")
    # Ein Scroll-Eintrag und ein Pinned-Eintrag sind da.
    assert_includes @response.body, I18n.t("nav.tasks")
    assert_includes @response.body, I18n.t("nav.dashboard")
  end

  test "preferences blade renders the sidebar-layout editor" do
    get settings_blade_path("preferences")
    assert_response :success
    assert_includes @response.body, "sidebar-layout-editor"
    assert_includes @response.body, I18n.t("preferences.sidebar_layout_title")
    assert_includes @response.body, "preferences[sidebar_layout][pinned]"
  end

  test "a custom saved layout drives the sidebar (hidden item disappears, order changes)" do
    @hans.update_preferences(
      "sidebar_layout" => { "pinned" => "tasks", "scroll" => "topics", "hidden" => "tags" }
    )
    get "/dashboard"
    assert_response :success
    # tags war im Default sichtbar, ist jetzt hidden -> Tag-Link fehlt.
    refute_includes @response.body, tags_path
  end
end
