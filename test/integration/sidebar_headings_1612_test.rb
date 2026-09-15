require "test_helper"

# #1612 (Hans): freie, aufklappbare Zwischenüberschriften in der Sidebar.
class SidebarHeadings1612Test < ActionDispatch::IntegrationTest
  setup do
    @hans = HumanActor.create!(name: "Hans", email: "hans-sh-#{SecureRandom.hex(3)}@t.local",
                               password: "secretsecret")
    %w[Task Topic KnowledgeItem Awaiting Communication Source Document].each { |res| grant(@hans, res, %w[read]) }
    grant(@hans, "Actor", %w[read update])
    post "/login", params: { email: @hans.email, password: "secretsecret" }
  end

  def mit_ueberschrift!(zu: false)
    @hans.update_preferences(
      "sidebar_headings" => { "a1b2c3d4" => "Arbeit" },
      "sidebar_layout"   => { "pinned" => "dashboard", "scroll" => "topics,heading:a1b2c3d4,tasks,knowledge", "hidden" => "" }
    )
    @hans.update_preferences("sidebar_collapsed_headings" => (zu ? "a1b2c3d4" : ""))
  end

  test "die festen Überschriften sind weg" do
    get "/dashboard"
    assert_response :success
    assert_select "aside nav", 1
    assert_select "aside", text: /#{I18n.t("shared.sidebar.recently_opened")}/i, count: 0
    assert_select "aside [data-sidebar-heading]", 0
  end

  test "eine Überschrift gruppiert die Einträge bis zum Ende des Bereichs" do
    mit_ueberschrift!
    get "/dashboard"
    assert_response :success
    assert_select "aside button[data-sidebar-heading='a1b2c3d4'][aria-expanded='true']", text: /Arbeit/
    assert_select "#sidebar-group-a1b2c3d4[data-zu='false']" do
      assert_select "a[href='#{tasks_path}']"
      assert_select "a[href='#{knowledge_items_path}']"
    end
    # Der Eintrag VOR der Überschrift gehört nicht zur Gruppe.
    assert_select "#sidebar-group-a1b2c3d4 a[href='#{topics_path}']", 0
  end

  test "eine zugeklappte Gruppe kommt zugeklappt vom Server" do
    mit_ueberschrift!(zu: true)
    get "/dashboard"
    assert_select "aside button[data-sidebar-heading='a1b2c3d4'][aria-expanded='false']"
    assert_select "#sidebar-group-a1b2c3d4[data-zu='true']"
  end

  test "Umklappen speichert per JSON in den Vorlieben" do
    mit_ueberschrift!
    patch settings_preferences_path, params: { preferences: { sidebar_collapsed_headings: "a1b2c3d4" } }, as: :json
    assert_response :ok
    assert_equal %w[a1b2c3d4], @hans.reload.pref_sidebar_collapsed_headings

    patch settings_preferences_path, params: { preferences: { sidebar_collapsed_headings: "" } }, as: :json
    assert_response :ok
    assert_empty @hans.reload.pref_sidebar_collapsed_headings
  end

  test "der Editor zeigt Überschriften als Zeile mit Namensfeld und den Knopf zum Hinzufügen" do
    mit_ueberschrift!
    get settings_blade_path("preferences")
    assert_response :success
    assert_select "li[data-item-id='heading:a1b2c3d4'] input[name='preferences[sidebar_headings][a1b2c3d4]'][value='Arbeit']"
    assert_select "button[data-action='sidebar-layout-editor#addHeading']", text: I18n.t("preferences.sidebar_heading_add")
  end

  test "das Vorlieben-Formular speichert Überschriften und Layout" do
    patch settings_preferences_path, params: { preferences: {
      sidebar_headings: { "c1c2c3c4" => "Privat" },
      sidebar_layout:   { pinned: "dashboard", scroll: "heading:c1c2c3c4,tasks", hidden: "" }
    } }
    assert_response :redirect
    @hans.reload
    assert_equal({ "c1c2c3c4" => "Privat" }, @hans.pref_sidebar_headings)
    assert_equal %w[heading:c1c2c3c4 tasks], @hans.pref_sidebar_layout["scroll"].first(2)
  end
end
