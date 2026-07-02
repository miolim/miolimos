require "test_helper"

# #768 (Hans): "Das bin ich" (Selbst-KI) + Mail-Sync-Policy-Toggle.
class Settings::SelfIdentityTest < ActionDispatch::IntegrationTest
  setup do
    @hans = HumanActor.create!(name: "Hans", email: "h-#{SecureRandom.hex(3)}@t.local",
                               password: "secretsecret", role: :admin)
    grant(@hans, "Actor",          %w[read update])
    grant(@hans, "OauthCredential", %w[read update])
    grant(@hans, "KnowledgeItem",   %w[read create update])
    post "/login", params: { email: @hans.email, password: "secretsecret" }
  end

  test "preferences-Blade zeigt 'Das bin ich' und speichert/löst die Selbst-KI" do
    with_isolated_miolimos_base do
      person = FileProxy.create(actor: @hans, title: "Hans Privat", item_type: :person,
                                content: "", topics: [], contacts: [], tags: [])
      get "/settings/blade/preferences"
      assert_response :success
      assert_includes @response.body, "Das bin ich"

      patch "/settings/preferences", params: { preferences: { person_ki_title: "Hans Privat" } }
      assert_equal person.uuid, @hans.reload.person_ki_uuid

      patch "/settings/preferences", params: { preferences: { person_ki_title: "" } }
      assert_nil @hans.reload.person_ki_uuid, "leer = Verknüpfung gelöst"
    end
  end

  test "accounts-Blade zeigt den Policy-Toggle und setzt das globale Setting" do
    get "/settings/blade/accounts"
    assert_response :success
    assert_includes @response.body, "Internen Team-Verkehr"

    assert Setting.sync_exclude_internal_team?, "Default = an (Policy B)"
    patch "/settings/accounts/sync_policy", params: {} # kein Häkchen → aus
    refute Setting.sync_exclude_internal_team?
    patch "/settings/accounts/sync_policy", params: { exclude_internal: "1" }
    assert Setting.sync_exclude_internal_team?
  end
end
