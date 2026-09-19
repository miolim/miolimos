require "application_system_test_case"

# #806: First-Run-Onboarding im echten Browser — jungfräuliche Instanz
# führt vom Login zum Setup, legt den Admin an und landet — weil noch kein
# zweiter Faktor eingerichtet ist (#1582) — auf der Sicherheits-Card.
class FirstRunTest < ApplicationSystemTestCase
  test "virgin instance onboards the first admin end-to-end" do
    visit "/login"
    assert_current_path "/setup"

    fill_in "human_actor[name]",                  with: "Erste Adminin"
    fill_in "human_actor[email]",                 with: "admin@instanz.example"
    fill_in "human_actor[password]",              with: "sehrsicher123"
    fill_in "human_actor[password_confirmation]", with: "sehrsicher123"
    click_on "Admin-Konto anlegen"

    # #1582: Wer noch keinen zweiten Faktor hat, sieht beim Start zuerst die
    # Sicherheits-Card — das gilt auch für die frisch angelegte Adminin. Der Test
    # erwartete weiter das Dashboard und war seit v0.5.0 rot.
    assert_current_path "/settings?stack=settings%3Asecurity"
    assert_selector ".stack-card[data-uuid='settings:security']", wait: 10
    admin = HumanActor.find_by(email: "admin@instanz.example")
    assert admin&.role == "admin"

    # Setup ist ab jetzt gesperrt
    visit "/setup"
    assert_current_path "/login"
  end
end
