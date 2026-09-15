require "test_helper"

# #1611 (Hans): „Eigenartige Vorschlagsliste für die Suche — es werden einzelne
# Zeichen angezeigt."
#
# Die Liste kam vom Browser, nicht von miolimOS: Das Suchformular im Seitenkopf
# schickt bei jedem Tastendruck ab, und der Browser merkte sich jeden halb
# getippten Begriff als Vorschlag. Ohne `autocomplete="off"` kommt das wieder.
class TopbarSearch1611Test < ActionDispatch::IntegrationTest
  setup do
    @hans = HumanActor.create!(name: "Hans", email: "suche-#{SecureRandom.hex(3)}@t.local",
                               password: "secretsecret")
    grant(@hans, "Task", %w[read])
    post "/login", params: { email: @hans.email, password: "secretsecret" }
  end

  test "das Suchfeld im Seitenkopf lässt keine Browser-Vorschläge zu" do
    get "/dashboard"
    assert_response :success
    assert_select "form[action='/search'] input[name='q'][autocomplete='off']", 1
  end
end
