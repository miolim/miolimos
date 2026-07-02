require "test_helper"

class Settings::TemplatesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @hans = HumanActor.create!(
      name: "Hans", email: "hans-st-#{SecureRandom.hex(3)}@t.local",
      password: "secretsecret"
    )
    grant(@hans, "Topic", %w[read])
    grant(@hans, "Actor", %w[read])
    post "/login", params: { email: @hans.email, password: "secretsecret" }
  end

  test "GET /settings/templates lists templates" do
    Topic.create!(name: "Template A", slug: "tpl-#{SecureRandom.hex(3)}",
                  template: true, creator: @hans)
    Topic.create!(name: "Regular",    slug: "reg-#{SecureRandom.hex(3)}",
                  template: false, creator: @hans)

    get "/settings/templates"
    follow_redirect!   # #613
    assert_response :success
    assert_includes @response.body, "Template A"
    # Templates-Sektion zeigt nur Vorlagen; "Regular" taucht aber auch
    # in der Sidebar-Navigation auf — deshalb Template-Slug-Präfix als
    # Präzisions-Anker prüfen.
    assert_includes @response.body, "tpl-"
  end
end
