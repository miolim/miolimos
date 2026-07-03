require "application_system_test_case"

# #806: First-Run-Onboarding im echten Browser — jungfräuliche Instanz
# führt vom Login zum Setup, legt den Admin an und landet im Dashboard.
class FirstRunTest < ApplicationSystemTestCase
  test "virgin instance onboards the first admin end-to-end" do
    visit "/login"
    assert_current_path "/setup"

    fill_in "human_actor[name]",                  with: "Erste Adminin"
    fill_in "human_actor[email]",                 with: "admin@instanz.example"
    fill_in "human_actor[password]",              with: "sehrsicher123"
    fill_in "human_actor[password_confirmation]", with: "sehrsicher123"
    click_on "Admin-Konto anlegen"

    assert_current_path "/dashboard"
    admin = HumanActor.find_by(email: "admin@instanz.example")
    assert admin&.role == "admin"

    # Setup ist ab jetzt gesperrt
    visit "/setup"
    assert_current_path "/login"
  end
end
