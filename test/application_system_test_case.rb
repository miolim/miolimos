# #206 Phase 1: System-Tests fuer Stimulus-Controller. Treiber: Cuprite
# (headless Chromium via CDP) — kein Selenium, kein WebDriver.
#
# Lokal: `bin/rails test:system` (laeuft NICHT als Teil von `bin/rails test`,
# damit Asset-Pipeline + Chromium nicht in jedem Lauf hochgefahren werden).
require "test_helper"
require "capybara/rails"
require "capybara/cuprite"

# #1496 (aus immoos #1459 uebernommen): Diese Optionen mussten aus
# `Capybara.register_driver(:cuprite)` hierher. Der Grund ist unangenehm:
# Rails' `driven_by :cuprite` REGISTRIERT DEN TREIBER NEU
# (ActionDispatch::SystemTesting::Driver#register) und ueberschreibt damit
# jede eigene Registrierung. Unsere Konfiguration war deshalb wirkungslos —
# im Browser kam `timeout = 5` an statt der hier gesetzten 15, und
# `pending_connection_errors` stand auf dem Standard.
#
# Das erklaert, warum die Suite als Ganzes unbrauchbar war: FUENF Sekunden
# fuer eine Seite, die ihre Controller als einzelne Dateien nachlaedt
# (importmap mit pin_all_from), von denen der Browser nur sechs gleichzeitig
# holt. Mal reicht es, mal nicht — und es trifft jedes Mal andere Tests.
# Gemessen an unserer Suite: vorher 2 Fehler und 39 Abbrueche, danach 0.
CUPRITE_OPTIONEN = {
  headless: !ENV["HEADED"],
  browser_options: { "no-sandbox" => nil },
  process_timeout: 30,
  timeout: 15,
  # Ferrum wartet beim Seitenaufruf auf NETZWERK-RUHE und meldet sonst die
  # offenen Anfragen als Fehler — obwohl die Seite laengst steht und nur noch
  # Controller nachladen. Was ein Test wirklich braucht, prueft er danach mit
  # `assert_selector`, und das wartet von sich aus.
  pending_connection_errors: false
}.freeze

Capybara.default_driver    = :cuprite
Capybara.javascript_driver = :cuprite
Capybara.default_max_wait_time = 5
Capybara.server = :puma, { Silent: true }

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  # Kopie, weil Rails die Optionen intern veraendert: Driver#initialize holt
  # sich `screen_size` mit `delete` heraus — an einer eingefrorenen Konstante
  # scheitert das mit FrozenError.
  driven_by :cuprite, screen_size: [1400, 900], options: CUPRITE_OPTIONEN.dup

  # #1496 (aus immoos #1459): Systemtests laufen mit ZWEI Workern.
  #
  # Der fruehere Kommentar hier behauptete, sie liefen gar nicht parallel.
  # Das stimmte nie: `parallelize` steht in test_helper.rb auf
  # ActiveSupport::TestCase, und ActionDispatch::SystemTestCase erbt davon.
  # Gelaufen sind sie also mit `number_of_processors` — und jeder Worker
  # bringt einen eigenen Chrome samt Server mit. Wer bei jedem Lauf andere
  # rote Tests sieht, gewoehnt sich an rot und uebersieht den echten Fehler.
  parallelize(workers: 2)

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
