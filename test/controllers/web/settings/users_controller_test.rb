require "test_helper"

# #927: Ein neu angelegter Benutzer bekam keine Capabilities und lief beim
# ersten Login in „… is not allowed to read Task". Create vergibt jetzt die
# Standard-Rechte (CapabilityDefaults.grant_full!).
class Settings::UsersControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin = HumanActor.create!(name: "Admin", email: "admin-#{SecureRandom.hex(3)}@t.local",
                                password: "secretsecret", role: :admin)
    grant(@admin, "Actor", %w[read create update delete])
    post "/login", params: { email: @admin.email, password: "secretsecret" }
  end

  test "Neuer Benutzer bekommt Standard-Capabilities und darf Task lesen (#927)" do
    assert_difference -> { HumanActor.count }, 1 do
      post "/settings/users", params: { human_actor: {
        name: "Peter Meurer", email: "peter-#{SecureRandom.hex(3)}@t.local", password: "secretsecret" } }
    end
    user = HumanActor.order(:id).last
    assert_equal "Peter Meurer", user.name

    cap = user.capabilities.find_by(resource_type: "Task", effect: :allow)
    assert cap.present?, "neuer Benutzer sollte eine Task-Capability haben"
    assert_equal CapabilityDefaults::HUMAN_ACTIONS.sort, cap.actions.sort

    # Genau der Fall aus der Fehlermeldung darf nicht mehr 403en.
    assert_nothing_raised { AccessGate.authorize!(actor: user, resource_type: "Task", action: "read") }
    # Vollrechte auf allen Standard-Resource-Types (inkl. Immobilien).
    CapabilityDefaults::RESOURCE_TYPES.each do |rt|
      assert user.capabilities.where(resource_type: rt, effect: :allow).exists?, "fehlt: #{rt}"
    end
  end
end
