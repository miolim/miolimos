# #206 Phase 1: System-Tests fuer Stimulus-Controller. Treiber: Cuprite
# (headless Chromium via CDP) — kein Selenium, kein WebDriver.
#
# Lokal: `bin/rails test:system` (laeuft NICHT als Teil von `bin/rails test`,
# damit Asset-Pipeline + Chromium nicht in jedem Lauf hochgefahren werden).
require "test_helper"
require "capybara/rails"
require "capybara/cuprite"

Capybara.register_driver(:cuprite) do |app|
  Capybara::Cuprite::Driver.new(app,
    window_size: [1400, 900],
    headless:    !ENV["HEADED"],
    browser_options: { "no-sandbox" => nil },
    # Default 5s ist zu knapp fuer den ersten Asset-Precompile-Treffer.
    process_timeout: 30,
    timeout: 15)
end

Capybara.default_driver    = :cuprite
Capybara.javascript_driver = :cuprite
Capybara.default_max_wait_time = 5
Capybara.server = :puma, { Silent: true }

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  driven_by :cuprite

  # System-Tests laufen ohne parallelize — der Browser-Driver hat
  # globalen Zustand, der nicht safe parallelisierbar ist.
  self.use_transactional_tests = true

  # Re-use die Factories aus dem normalen test_helper.
  include ActiveSupport::Testing::SetupAndTeardown

  # #801: role: :admin als Default — angeglichen an die Factory im
  # test_helper (#602 S1: entspricht dem Bestand vor Multi-User; Member-
  # Verhalten testen die Isolations-Tests explizit). Ohne Admin sah der
  # Test-Hans z.B. Dokumente ohne Topic/Creator nicht mehr.
  def create_human(email: "hans-#{SecureRandom.hex(4)}@test.local", name: "Hans",
                   role: :admin, password: "secretsecret")
    HumanActor.create!(name: name, email: email, active: true, role: role, password: password)
  end

  def grant(actor, resource_type, actions, effect: :allow)
    cap = Capability.where(actor: actor, resource_type: resource_type, effect: effect).first_or_initialize
    cap.actions = Array(actions).map(&:to_s)
    cap.save!
    cap
  end

  def login_as(actor, password: "secretsecret")
    visit "/login"
    fill_in "email",    with: actor.email
    fill_in "password", with: password
    click_button(class: "btn") rescue click_on "Anmelden"
  end
end
