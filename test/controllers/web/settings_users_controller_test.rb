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

  # #1520 (Hans): „Passwort für andere Nutzer ändern bitte an Admin-Rechte
  # binden." Dieser Test forderte bis dahin das GEGENTEIL — er hielt fest,
  # dass jeder mit Actor-Rechten das Passwort jedes anderen setzen kann.
  # Umgedreht statt gelöscht: Er hält jetzt fest, dass es nicht zurückkommt.
  test "PATCH update: ein Admin dreht das Passwort eines anderen" do
    @hans.update!(role: :admin)
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

  # Der Kern der Änderung. `@hans` ist hier bewusst KEIN Admin — er hat volle
  # Actor-Rechte, und genau die reichten vorher aus.
  test "PATCH update: ohne Admin-Recht bleibt das fremde Passwort stehen" do
    assert_not @hans.admin?, "Vorbedingung: der Nutzer ist Member mit vollen Actor-Rechten"
    user = HumanActor.create!(
      name: "User", email: "kein-#{SecureRandom.hex(3)}@t.local",
      password: "originalpass"
    )
    old_digest = user.password_digest

    patch "/settings/users/#{user.id}", params: {
      human_actor: { name: user.name, email: user.email, password: "differentpass" }
    }

    assert_redirected_to "/settings/users"
    assert_equal I18n.t("settings.users.password_admin_only"), flash[:alert]
    assert_equal old_digest, user.reload.password_digest,
                 "das Passwort darf sich nicht geändert haben"
    assert user.authenticate("originalpass"), "und das alte muss weiter gelten"
  end

  # Abgewiesen wird das PASSWORT, nicht der ganze Vorgang: Wer Benutzer
  # verwalten darf, darf weiter Namen und Adresse pflegen. Hans hat genau
  # eine Sache genannt — die Grenze steht hier, damit sie nicht unbemerkt
  # weiter wandert.
  test "PATCH update: die übrigen Felder bleiben auch ohne Admin-Recht änderbar" do
    user = HumanActor.create!(
      name: "User", email: "feld-#{SecureRandom.hex(3)}@t.local",
      password: "originalpass"
    )
    patch "/settings/users/#{user.id}", params: {
      human_actor: { name: "Umbenannt", email: user.email, password: "" }
    }
    assert_equal "Umbenannt", user.reload.name
  end

  # Das eigene Passwort bleibt hier möglich — gebunden ist das Passwort
  # ANDERER. (Der bequeme Weg dafür steht seit #1520 unter Sicherheit.)
  test "PATCH update: das eigene Passwort darf man weiter selbst setzen" do
    old_digest = @hans.password_digest
    patch "/settings/users/#{@hans.id}", params: {
      human_actor: { name: @hans.name, email: @hans.email, password: "meinneuespw" }
    }
    assert_not_equal old_digest, @hans.reload.password_digest
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
