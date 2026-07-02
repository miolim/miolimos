require "test_helper"

class PromptTemplatesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @hans = HumanActor.create!(
      name: "Hans", email: "hans-pt-#{SecureRandom.hex(3)}@t.local",
      password: "secretsecret"
    )
    grant(@hans, "PromptTemplate", %w[read create update delete])
    grant(@hans, "Actor", %w[read])   # #613: Settings-Stack-Gate
    post "/login", params: { email: @hans.email, password: "secretsecret" }
  end

  def make_template(attrs = {})
    PromptTemplate.create!({
      name: "Default", slug: "default-#{SecureRandom.hex(3)}",
      prompt_text: "tu was", creator: @hans
    }.merge(attrs))
  end

  test "GET index lists templates" do
    t = make_template(name: "Article Summary")
    get "/prompt_templates"
    follow_redirect!   # #613
    assert_response :ok
    assert_includes @response.body, t.name
  end

  test "GET show renders template" do
    t = make_template
    get "/prompt_templates/#{t.slug}"
    follow_redirect!   # #613 St.2: Detail ist ein Blade im Stack
    assert_response :ok
  end

  test "POST create derives slug from name when slug is blank" do
    assert_difference -> { PromptTemplate.count }, 1 do
      post "/prompt_templates", params: {
        prompt_template: { name: "Mein Prompt", prompt_text: "do x" }
      }
    end
    pt = PromptTemplate.last
    assert_equal "mein-prompt", pt.slug
    assert_includes @response.redirect_url, "prompt_templates%3Amein-prompt"  # #613 St.2: Stack-URL
  end

  test "POST create with invalid input re-renders form" do
    assert_no_difference -> { PromptTemplate.count } do
      post "/prompt_templates", params: { prompt_template: { name: "" } }
    end
    assert_response :unprocessable_entity
  end

  test "PATCH update with stable slug changes only the name" do
    t = make_template(name: "Old")
    patch "/prompt_templates/#{t.slug}", params: {
      prompt_template: { name: "New", slug: t.slug, prompt_text: t.prompt_text }
    }
    assert_includes @response.redirect_url, "prompt_templates%3A#{t.slug}"  # #613 St.2: Stack-URL
    assert_equal "New", t.reload.name
    assert_equal t.slug, t.reload.slug
  end

  test "PATCH update without slug auto-derives slug from new name" do
    t = make_template(name: "Old", slug: "old-#{SecureRandom.hex(3)}")
    patch "/prompt_templates/#{t.slug}", params: {
      prompt_template: { name: "Brand New Name", prompt_text: t.prompt_text }
    }
    t.reload
    assert_equal "brand-new-name", t.slug
    assert_includes @response.redirect_url, "prompt_templates%3Abrand-new-name"  # #613 St.2: Stack-URL
  end

  test "DELETE destroys template" do
    t = make_template
    assert_difference -> { PromptTemplate.count }, -1 do
      delete "/prompt_templates/#{t.slug}"
    end
    assert_redirected_to "/prompt_templates"
  end

  test "without PromptTemplate.delete capability, DELETE is forbidden" do
    other = HumanActor.create!(
      name: "Eve", email: "eve-#{SecureRandom.hex(3)}@t.local",
      password: "secretsecret"
    )
    grant(other, "PromptTemplate", %w[read create update])
    post "/login", params: { email: other.email, password: "secretsecret" }

    t = make_template
    delete "/prompt_templates/#{t.slug}"
    assert_response :forbidden
    assert PromptTemplate.exists?(t.id)
  end
end
