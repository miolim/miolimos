require "test_helper"

# #1109: Smoke-Test — die layout-getriebene Topbar und der Vorlieben-Editor
# rendern fehlerfrei (uebt shared/_topbar_item fuer alle IDs + die
# pref_topbar_layout-Berechnung). Muster: sidebar_layout_render_test.rb.
class TopbarLayoutRenderTest < ActionDispatch::IntegrationTest
  setup do
    @hans = HumanActor.create!(
      name: "Hans", email: "hans-tb-#{SecureRandom.hex(3)}@t.local",
      password: "secretsecret"
    )
    %w[Task Topic KnowledgeItem Awaiting Communication Source Document Actor].each do |res|
      grant(@hans, res, %w[read])
    end
    post "/login", params: { email: @hans.email, password: "secretsecret" }
  end

  test "dashboard renders the layout-driven topbar with default layout" do
    get "/dashboard"
    assert_response :success
    # Quick-Create-Icon (links) und Diagnose-Knopf (rechts) sind da.
    assert_includes @response.body, I18n.t("shared.quick_create.task_aria")
    assert_includes @response.body, I18n.t("shared.topbar.diagnostic_label")
    # Der quick-create-Controller sitzt auf dem Header (#1109), die Slots
    # sind weiter im Scope.
    assert_includes @response.body, 'data-controller="keyboard blade-counts quick-create"'
    assert_includes @response.body, 'data-quick-create-target="slot"'
  end

  # #1198: Stack-Schritt-Pfeile links neben dem Suchfeld — immer im
  # Markup (CSS blendet sie auf Seiten ohne Card-Stack aus), initial
  # disabled, bis der Trail-Mixin die Zustände nachzieht.
  test "topbar renders the stack trail arrows left of the search field" do
    get "/dashboard"
    assert_response :success
    assert_includes @response.body, 'id="topbar_trail_back"'
    assert_includes @response.body, 'id="topbar_trail_forward"'
    assert_includes @response.body, I18n.t("knowledge.form.trail_back_title")
    back_pos   = @response.body.index('id="topbar_trail_back"')
    search_pos = @response.body.index('data-controller="search-collapse"')
    assert back_pos < search_pos, "Pfeile müssen vor dem Suchfeld stehen"
  end

  test "a custom saved layout drives the topbar (hidden item disappears, zones change)" do
    @hans.update_preferences(
      "topbar_layout" => { "left" => "quick_task", "right" => "theme,quick_inbox", "hidden" => "diagnostic,inspector,shortcuts,timer,quick_awaiting,quick_ki,quick_person" }
    )
    get "/dashboard"
    assert_response :success
    # Ausgeblendete Icons fehlen komplett. Die *_title-Strings sind eindeutig
    # (die kurzen Labels tauchen auch im MIO_I18N-JS-Dump jeder Seite auf).
    refute_includes @response.body, I18n.t("shared.topbar.diagnostic_title")
    refute_includes @response.body, I18n.t("shared.topbar.inspector_title")
    refute_includes @response.body, I18n.t("shared.quick_create.person_title")
    # In die rechte Zone verschobenes Quick-Create-Icon ist weiter da.
    assert_includes @response.body, I18n.t("shared.quick_create.inbox_title")
  end

  test "preferences blade renders the topbar-layout editor" do
    get settings_blade_path("preferences")
    assert_response :success
    assert_includes @response.body, I18n.t("preferences.topbar_layout_title")
    assert_includes @response.body, "preferences[topbar_layout][left]"
    # Eigene Sortable-Gruppe, damit man nicht zwischen Sidebar- und
    # Topbar-Editor ziehen kann.
    assert_includes @response.body, 'data-sidebar-layout-editor-group-value="topbar-layout"'
  end
end
