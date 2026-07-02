require "test_helper"

# #801 P1: CRUD-Tests für die Settings-Vorlagen-Controller (KI- und
# Task-Vorlagen) — beide waren komplett ungetestet.
class SettingsKiTaskTemplatesTest < ActionDispatch::IntegrationTest
  setup do
    @hans = HumanActor.create!(
      name: "Hans", email: "hans-tpl-#{SecureRandom.hex(3)}@t.local",
      password: "secretsecret"
    )
    grant(@hans, "Actor", %w[read create update delete])
    post "/login", params: { email: @hans.email, password: "secretsecret" }
  end

  # ── KI-Vorlagen ────────────────────────────────────────────────────────

  test "ki_templates: GET index redirects to the settings stack (#613)" do
    get "/settings/ki_templates"
    assert_redirected_to "/settings?stack=list%3Asettings%2Csettings%3Aki_templates"
  end

  test "ki_templates: POST create persists template" do
    assert_difference -> { KiTemplate.count }, 1 do
      post "/settings/ki_templates", params: {
        ki_template: { name: "Notiz-Vorlage", item_type: "note",
                       title: "Neue Notiz", body: "Inhalt" }
      }
    end
    assert_redirected_to "/settings/ki_templates"
    tpl = KiTemplate.order(:created_at).last
    assert_equal "Notiz-Vorlage", tpl.name
  end

  test "ki_templates: PATCH update changes template" do
    tpl = KiTemplate.create!(name: "Alt", item_type: "note", title: "T", body: "B")
    patch "/settings/ki_templates/#{tpl.id}",
          params: { ki_template: { name: "Neu" } }
    assert_redirected_to "/settings/ki_templates"
    assert_equal "Neu", tpl.reload.name
  end

  test "ki_templates: DELETE removes template" do
    tpl = KiTemplate.create!(name: "Weg", item_type: "note", title: "T", body: "B")
    assert_difference -> { KiTemplate.count }, -1 do
      delete "/settings/ki_templates/#{tpl.id}"
    end
    assert_redirected_to "/settings/ki_templates"
  end

  # ── Task-Vorlagen ──────────────────────────────────────────────────────

  test "task_templates: GET index redirects to the settings stack (#613)" do
    get "/settings/task_templates"
    assert_redirected_to "/settings?stack=list%3Asettings%2Csettings%3Atask_templates"
  end

  test "task_templates: POST create persists template with agent assignment" do
    agent = create_agent
    assert_difference -> { TaskTemplate.count }, 1 do
      post "/settings/task_templates", params: {
        task_template: { title: "Wochenbericht", description: "Bitte erstellen",
                         agent_actor_id: agent.id }
      }
    end
    assert_redirected_to "/settings/task_templates"
    tpl = TaskTemplate.order(:created_at).last
    assert_equal "Wochenbericht", tpl.title
    assert_equal agent.id, tpl.agent_actor_id
  end

  test "task_templates: PATCH update changes template" do
    tpl = TaskTemplate.create!(title: "Alt")
    patch "/settings/task_templates/#{tpl.id}",
          params: { task_template: { title: "Neu" } }
    assert_redirected_to "/settings/task_templates"
    assert_equal "Neu", tpl.reload.title
  end

  test "task_templates: DELETE removes template" do
    tpl = TaskTemplate.create!(title: "Weg")
    assert_difference -> { TaskTemplate.count }, -1 do
      delete "/settings/task_templates/#{tpl.id}"
    end
    assert_redirected_to "/settings/task_templates"
  end
end
