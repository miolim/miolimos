require "application_system_test_case"

# Smallest possible smoke test — proves Cuprite + Capybara wired up.
class SmokeTest < ApplicationSystemTestCase
  test "login page renders and rejects unknown user" do
    visit "/login"
    assert page.has_field?("email")
    assert page.has_field?("password")
    fill_in "email",    with: "nobody@test.local"
    fill_in "password", with: "wrong"
    click_on "Anmelden"
    # Failed login bleibt auf /login mit Alert.
    assert_current_path "/login", ignore_query: true
  end

  test "login + dashboard fuer authentifizierten User" do
    hans = create_human
    grant(hans, "Topic", %w[read])
    grant(hans, "Task", %w[read])

    login_as(hans)
    assert_current_path "/dashboard"
    refute page.has_field?("email"), "Login-Form sollte nach Login verschwunden sein"
  end
end
