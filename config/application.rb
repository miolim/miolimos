require_relative "boot"

require "rails"
# Pick the frameworks you want:
require "active_model/railtie"
require "active_job/railtie"
require "active_record/railtie"
require "active_storage/engine"
require "action_controller/railtie"
require "action_mailer/railtie"
require "action_mailbox/engine"
require "action_text/engine"
require "action_view/railtie"
require "action_cable/engine"   # #232 Phase 0: Live-Updates via Turbo Streams
require "rails/test_unit/railtie"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module Miolimos
  # #745: Single source of truth for the app version (SemVer). The VERSION
  # file at the repo root is read by everything that needs the number —
  # this constant (UI display), the CHANGELOG, release Git-Tags and the
  # tagged Docker image. Bump the file, not a literal scattered in code.
  VERSION = File.read(File.expand_path("../VERSION", __dir__)).strip.freeze

  class Application < Rails::Application
    # #536: Portal-Host-Isolation als Middleware (siehe app/middleware/).
    require_relative "../app/middleware/portal_host_guard"
    config.middleware.use PortalHostGuard

    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.1

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")

    # Don't generate system test files.
    config.generators.system_tests = nil

    # Deutsche Lokalisierung als Default — das UI ist deutschsprachig.
    # Fallback auf :en, damit Rails-Default-Fehlermeldungen wie "can't be
    # blank" und Attribut-Namen greifen, solange de.yml sie nicht liefert.
    config.i18n.default_locale = :de
    config.i18n.available_locales = [:de, :en]
    config.i18n.fallbacks = [:en]
    config.time_zone = "Berlin"

    # Per-form CSRF-Tokens passen in unserer Rails-8.1 + CookieStore-
    # Session-Kombination nicht zwischen Render und Submit zusammen — alle
    # POSTs scheiterten mit InvalidAuthenticityToken. Globale CSRF-Tokens
    # funktionieren und sind weiterhin voll wirksam. TODO: Root-Cause
    # später nachziehen.
    config.action_controller.per_form_csrf_tokens = false

    # Schema-Dump als SQL (statt Ruby), damit PG-spezifische Sachen
    # — Trigger, Funktionen, Generated Columns, GIN-Indexe auf Expressions
    # — beim db:test:prepare/load mitkommen. db/schema.rb hätte die
    # search_vector-Trigger einfach geschluckt.
    config.active_record.schema_format = :sql
  end
end
