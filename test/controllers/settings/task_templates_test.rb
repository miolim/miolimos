require "test_helper"

# #1054: Aufgabenvorlagen — Edit lief seit #613 auf eine gelöschte
# index-View (500 bei jedem Bearbeiten-Klick). Jetzt: Edit als
# settingssub-Blade, Fehlerpfade als Alert-Redirects.
class SettingsTaskTemplatesTest < ActionDispatch::IntegrationTest
  setup do
    @hans = create_human(password: "secretsecret")
    CapabilityDefaults.grant_full!(@hans)
    post "/login", params: { email: @hans.email, password: "secretsecret" }
    @tpl = TaskTemplate.create!(title: "04 Testabdeckung", description: "Bitte …")
  end

  test "edit leitet in den Stack mit dem Edit-Sub-Blade" do
    get "/settings/task_templates/#{@tpl.id}/edit"
    assert_redirected_to %r{settingssub%3Atask_templates%3A#{@tpl.id}%3Aedit|settingssub:task_templates:#{@tpl.id}:edit}
  end

  test "Edit-Sub-Blade rendert die Form (500-Regression)" do
    get "/settings/blade/task_templates/sub/#{@tpl.id}:edit"
    assert_response :success
    assert_includes response.body, "Vorlage: #{@tpl.title}"
    assert_includes response.body, @tpl.description
  end

  test "update speichert und redirected in den Stack" do
    patch "/settings/task_templates/#{@tpl.id}",
          params: { task_template: { title: "04 Testabdeckung & Refactoring",
                                     description: "**Ablauf:** …", agent_actor_id: "" } }
    assert_response :redirect
    @tpl.reload
    assert_equal "04 Testabdeckung & Refactoring", @tpl.title
    assert_nil @tpl.agent_actor_id
  end

  test "update mit leerem Titel: Alert-Redirect statt 500" do
    patch "/settings/task_templates/#{@tpl.id}", params: { task_template: { title: "" } }
    assert_response :redirect
    assert flash[:alert].present?
    assert_equal "04 Testabdeckung", @tpl.reload.title
  end

  test "create mit leerem Titel: Alert-Redirect statt 500" do
    post "/settings/task_templates", params: { task_template: { title: "", description: "x" } }
    assert_response :redirect
    assert flash[:alert].present?
  end

  test "gelöschte Vorlage im Sub-Blade: leises Leer-Rendering statt Fehler" do
    id = @tpl.id
    @tpl.destroy!
    get "/settings/blade/task_templates/sub/#{id}:edit"
    assert_response :success
    assert_not_includes response.body, "stack_card_settingssub:task_templates:#{id}:edit"
  end
end
