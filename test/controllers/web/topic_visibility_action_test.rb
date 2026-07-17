require "test_helper"

# #1055 (Lücke): multi_user_isolation_test prüft die WIRKUNG von
# Sichtbarkeit gründlich, setzte sie aber nur per update! in Fixtures.
# Hier die Mutations-Action selbst: PATCH /topics/:id/visibility mit
# Stewardship-Gate (#602 S3) — ein Nicht-Verantwortlicher darf ein Topic
# nicht auf internal_public schalten (würde den Teilbaum exponieren).
class TopicVisibilityActionTest < ActionDispatch::IntegrationTest
  setup do
    @admin  = create_human(name: "Adminka", password: "secretsecret")
    CapabilityDefaults.grant_full!(@admin)
    @member = create_human(name: "Momo", role: :member, password: "secretsecret")
    CapabilityDefaults.grant_full!(@member)
    @topic = Topic.create!(name: "Geheimprojekt-#{SecureRandom.hex(3)}", creator: @admin)
  end

  test "Verantwortlicher (Admin) schaltet Sichtbarkeit um" do
    post "/login", params: { email: @admin.email, password: "secretsecret" }
    patch "/topics/#{@topic.slug}/visibility", params: { visibility: "internal_public" }
    assert_response :success
    assert_equal "internal_public", @topic.reload.visibility
  end

  test "Editor-Mitglied ohne Stewardship wird geblockt und ändert nichts" do
    TopicMembership.create!(topic: @topic, actor: @member, role: "editor")
    post "/login", params: { email: @member.email, password: "secretsecret" }
    patch "/topics/#{@topic.slug}/visibility", params: { visibility: "internal_public" }
    assert_response :forbidden
    assert_equal "members_only", @topic.reload.visibility
  end

  test "Außenstehender sieht das Topic gar nicht (404 statt Leak)" do
    post "/login", params: { email: @member.email, password: "secretsecret" }
    patch "/topics/#{@topic.slug}/visibility", params: { visibility: "internal_public" }
    assert_response :not_found
    assert_equal "members_only", @topic.reload.visibility
  end
end
