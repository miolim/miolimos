require "application_system_test_case"

# #1612 (Hans): „Die sollen auch wie Aufklapp-Menüs funktionieren" — und der
# Zustand bleibt in den Vorlieben (a). Das Umschalten ist JavaScript, deshalb
# hier im Browser.
class SidebarHeadingsSystem1612Test < ApplicationSystemTestCase
  setup do
    @hans = create_human
    %w[Task Topic KnowledgeItem Awaiting Communication Source Document].each { |res| grant(@hans, res, %w[read]) }
    grant(@hans, "Actor", %w[read update])
    login_as(@hans)
  end

  def aufgaben_link = "aside a[href='#{tasks_path}']"

  test "Klick klappt die Gruppe zu, und sie bleibt nach dem Neuladen zu" do
    @hans.update_preferences(
      "sidebar_headings" => { "a1b2c3d4" => "Arbeit" },
      "sidebar_layout"   => { "pinned" => "dashboard", "scroll" => "heading:a1b2c3d4,tasks", "hidden" => "" }
    )
    visit "/dashboard"
    assert_selector aufgaben_link, visible: true

    find("aside button[data-sidebar-heading='a1b2c3d4']").click
    assert_no_selector aufgaben_link, visible: true, wait: 3
    # Gespeichert wird im Hintergrund — warten, bis es in den Vorlieben steht.
    assert(Array.new(30) { |i| sleep 0.1 if i.positive?; @hans.reload.pref_sidebar_collapsed_headings }.any?(%w[a1b2c3d4]),
           "Zugeklappt muss in den Vorlieben landen")

    visit "/dashboard"
    assert_no_selector aufgaben_link, visible: true
    find("aside button[data-sidebar-heading='a1b2c3d4']").click
    assert_selector aufgaben_link, visible: true, wait: 3
  end

  test "im Editor eine Überschrift anlegen, benennen und speichern" do
    visit "/settings?stack=list:settings,settings:preferences"
    click_on I18n.t("preferences.sidebar_heading_add")
    feld = find("li[data-item-id^='heading:'] input[type='text']")
    feld.fill_in with: "Projekte"
    click_on I18n.t("preferences.save", default: "Speichern")

    assert(Array.new(30) { |i| sleep 0.1 if i.positive?; @hans.reload.pref_sidebar_headings.values }.any?(["Projekte"]),
           "Die Überschrift muss gespeichert sein")
    visit "/dashboard"
    assert_selector "aside button[data-sidebar-heading]", text: /Projekte/i
  end
end
