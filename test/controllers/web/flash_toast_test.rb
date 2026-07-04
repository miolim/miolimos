require "test_helper"

# #809: Flash-Meldungen aus Redirect-Flows rendern als auto-dismissende
# Toasts im toast_stack — nicht mehr als statische Banner im <main>.
class FlashToastTest < ActionDispatch::IntegrationTest
  setup do
    @hans = HumanActor.create!(
      name: "Hans", email: "hans-ft-#{SecureRandom.hex(3)}@t.local",
      password: "secretsecret"
    )
    grant(@hans, "Topic", %w[read create update delete])
    grant(@hans, "Task", %w[read])
    post "/login", params: { email: @hans.email, password: "secretsecret" }
  end

  test "redirect notice renders as toast in the toast stack" do
    post "/topics", params: { topic: { name: "Toast-Probe", slug: "toast-probe-#{SecureRandom.hex(3)}" } }
    assert_response :redirect
    follow_redirect!
    assert_response :ok

    # Meldung liegt IM toast_stack und trägt den Auto-Dismiss-Controller …
    stack = @response.body[/<div id="toast_stack".*?<\/div>\s*<\/div>/m]
    assert stack, "toast_stack muss im Layout liegen"
    assert_includes stack, 'data-controller="toast"'
    # … und nicht mehr als statisches Banner im main
    assert_not_includes @response.body, "border-emerald-200 bg-emerald-50 px-3 py-2 text-emerald-800"
  end
end
