require "test_helper"

class Settings::UsersControllerTest < ActionDispatch::IntegrationTest
  setup do
    @hans = HumanActor.create!(
      name: "Hans", email: "hans-su-#{SecureRandom.hex(3)}@t.local",
      password: "secretsecret"
    )
    grant(@hans, "Actor", %w[read create update delete])
    post "/login", params: { email: @hans.email, password: "secretsecret" }
  end

  test "GET index lists users" do
    other = HumanActor.create!(
      name: "Other", email: "other-#{SecureRandom.hex(3)}@t.local",
      password: "secretsecret"
    )
    get "/settings/users"
    follow_redirect!   # #613: Reiter-URL leitet auf den Stack
    assert_response :ok
    assert_includes @response.body, other.name
  end

  test "POST create persists new user" do
    email = "new-#{SecureRandom.hex(3)}@t.local"
    assert_difference -> { HumanActor.count }, 1 do
      post "/settings/users", params: {
        human_actor: { name: "Neu", email: email, password: "longenough", active: true }
      }
    end
    assert_redirected_to "/settings/users"
    assert HumanActor.find_by(email: email)
  end

  test "POST create with invalid params re-renders form" do
    assert_no_difference -> { HumanActor.count } do
      post "/settings/users", params: {
        human_actor: { name: "", email: "" }
      }
    end
    assert_response :unprocessable_entity
  end

  test "PATCH update with blank password keeps old digest" do
    user = HumanActor.create!(
      name: "User", email: "update-#{SecureRandom.hex(3)}@t.local",
      password: "originalpass"
    )
    old_digest = user.password_digest

    patch "/settings/users/#{user.id}", params: {
      human_actor: { name: "Renamed", email: user.email, password: "" }
    }
    assert_redirected_to "/settings/users"
    user.reload
    assert_equal "Renamed", user.name
    assert_equal old_digest, user.password_digest
  end

  test "PATCH update with new password rotates digest" do
    user = HumanActor.create!(
      name: "User", email: "rot-#{SecureRandom.hex(3)}@t.local",
      password: "originalpass"
    )
    old_digest = user.password_digest

    patch "/settings/users/#{user.id}", params: {
      human_actor: { name: user.name, email: user.email, password: "differentpass" }
    }
    assert_not_equal old_digest, user.reload.password_digest
  end

  test "DELETE removes user" do
    user = HumanActor.create!(
      name: "Goner", email: "del-#{SecureRandom.hex(3)}@t.local",
      password: "originalpass"
    )
    assert_difference -> { HumanActor.count }, -1 do
      delete "/settings/users/#{user.id}"
    end
    assert_redirected_to "/settings/users"
  end

  test "DELETE on self redirects with alert and does not destroy" do
    assert_no_difference -> { HumanActor.count } do
      delete "/settings/users/#{@hans.id}"
    end
    assert_redirected_to "/settings/users"
    assert HumanActor.exists?(@hans.id)
  end
end
