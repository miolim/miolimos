require "test_helper"

# #456 (Hans, 2026-06-02): /tags als vollwertige Blade-Stack-Seite.
class TagsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @hans = HumanActor.create!(
      name: "Hans", email: "hans-tags-#{SecureRandom.hex(3)}@t.local",
      password: "secretsecret"
    )
    %w[Task Topic Contact KnowledgeItem Communication].each { |r| grant(@hans, r, %w[read create update delete]) }
    post "/login", params: { email: @hans.email, password: "secretsecret" }
  end

  test "GET /tags rendert die Tag-Liste als Blade-Stack-Starter" do
    Task.create!(title: "Getaggte Aufgabe", creator: @hans, status: :open, tags: ["wichtig-xz"])
    get "/tags"
    assert_response :success
    assert_match %r{data-uuid="list:tags"}, @response.body
    assert_match %r{data-blade-stack-history-storage-key-value="tags.stack.history"}, @response.body
    assert_includes @response.body, "wichtig-xz"
  end
end
