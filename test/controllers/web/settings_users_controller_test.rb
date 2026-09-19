require "test_helper"

class Settings::UsersControllerTest < ActionDispatch::IntegrationTest
  setup do
    # #1675: Benutzer verwalten ist Admin-Sache — der Verwalter hier ist einer.
    # Was Nicht-Admins (nicht) dürfen: settings_admin_only_1675_test.rb.
    @hans = HumanActor.create!(
      name: "Hans", email: "hans-su-#{SecureRandom.hex(3)}@t.local",
      password: "secretsecret", role: :admin
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

  # Der Kern von #1520. `@hans` ist hier bewusst KEIN Admin — er hat volle
  # Actor-Rechte, und genau die reichten vorher aus. #1675: Seither wird der
  # ganze Vorgang abgewiesen (403), nicht nur das Passwortfeld.
  test "PATCH update: ohne Admin-Recht bleibt das fremde Passwort stehen" do
    @hans.update!(role: :member)
    user = HumanActor.create!(
      name: "User", email: "kein-#{SecureRandom.hex(3)}@t.local",
      password: "originalpass"
    )
    old_digest = user.password_digest

    patch "/settings/users/#{user.id}", params: {
      human_actor: { name: user.name, email: user.email, password: "differentpass" }
    }

    assert_response :forbidden
    assert_equal old_digest, user.reload.password_digest,
                 "das Passwort darf sich nicht geändert haben"
    assert user.authenticate("originalpass"), "und das alte muss weiter gelten"
  end

  # #1520 hielt hier fest: „Abgewiesen wird das PASSWORT, nicht der ganze
  # Vorgang — die übrigen Felder bleiben auch ohne Admin-Recht änderbar."
  # #1675 (Hans, 19.09.2026) nimmt das zurück: Über das Feld E-Mail lief
  # dieselbe Konto-Übernahme, nur einen Schritt länger (Adresse ändern, dann
  # „Passwort vergessen"). Umgedreht statt gelöscht — wie schon sein Vorgänger.
  test "PATCH update: ohne Admin-Recht sind auch die übrigen Felder eines anderen tabu" do
    @hans.update!(role: :member)
    user = HumanActor.create!(
      name: "User", email: "feld-#{SecureRandom.hex(3)}@t.local",
      password: "originalpass"
    )
    patch "/settings/users/#{user.id}", params: {
      human_actor: { name: "Umbenannt", email: "uebernahme@t.local", password: "" }
    }
    assert_response :forbidden
    assert_equal "User", user.reload.name
    refute_equal "uebernahme@t.local", user.email
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

  # #1675: Wer Inhalte angelegt hat, ließ sich nicht sauber löschen — Themen
  # tragen creator_id NOT NULL, das „nullify" endete in einer Fehlerseite (500);
  # und seine Wartepunkte wären per dependent: :destroy mitgelöscht worden.
  # Jetzt: abgewiesen mit dem Hinweis, stattdessen zu deaktivieren.
  test "DELETE: ein Nutzer mit eigenen Inhalten wird nicht geloescht, sondern zum Deaktivieren verwiesen" do
    user = HumanActor.create!(
      name: "Autorin", email: "aut-#{SecureRandom.hex(3)}@t.local", password: "originalpass"
    )
    create_topic(creator: user, name: "Ihr Thema", slug: "ihr-#{SecureRandom.hex(3)}")
    wp = Awaiting.create!(creator: user, title: "Ihr Wartepunkt", status: :open, follow_up_at: 1.week.from_now)

    assert_no_difference -> { HumanActor.count } do
      delete "/settings/users/#{user.id}"
    end
    assert_redirected_to "/settings/users"
    assert_equal I18n.t("settings.users.delete_has_content", name: user.name), flash[:alert]
    assert Awaiting.exists?(wp.id), "ihre Wartepunkte wurden mitgelöscht"
  end

  test "DELETE on self redirects with alert and does not destroy" do
    assert_no_difference -> { HumanActor.count } do
      delete "/settings/users/#{@hans.id}"
    end
    assert_redirected_to "/settings/users"
    assert HumanActor.exists?(@hans.id)
  end
end
