source "https://rubygems.org"

# Bundle edge Rails instead: gem "rails", github: "rails/rails", branch: "main"
gem "rails", "~> 8.1.2"
# The modern asset pipeline for Rails [https://github.com/rails/propshaft]
gem "propshaft"
# Use postgresql as the database for Active Record
gem "pg", "~> 1.1"
# Use the Puma web server [https://github.com/puma/puma]
gem "puma", ">= 5.0"
# Build JSON APIs with ease [https://github.com/rails/jbuilder]
gem "jbuilder"

gem "bcrypt", "~> 3.1.7"

# Phase 4: Web-UI – Turbo, Stimulus, Tailwind, Markdown
gem "importmap-rails"
gem "turbo-rails"
gem "stimulus-rails"
gem "tailwindcss-rails"
gem "redcarpet"

# #625 (Hans): GiroCode/EPC-QR auf Rechnungen + Überweisungs-Formular —
# reines Ruby, keine nativen Extensions.
gem "rqrcode"

# #536: ZIP-Erzeugung für den statischen Portal-Export (kein zip-CLI auf der Box).
gem "rubyzip", require: "zip"

# #573 v2: Termine zusätzlich in den Google-Kalender schreiben (Push-Spiegel;
# braucht den calendar.events-Scope an der Gmail-Credential).
gem "google-apis-calendar_v3"

# #562: Headless-Chrome via CDP für PDF-Render MIT Kopf-/Fußzeile (Seitenzahlen,
# Dokument-ID) und echten Seitenrändern — die CLI (--print-to-pdf) kann das nicht.
# Bereits über cuprite (test) im Lockfile; hier für die Produktion explizit.
gem "ferrum"

# CORS für /api/v1/* — wird vom Browser-Add-on (chrome-extension://…)
# und perspektivisch anderen externen Clients gerufen.
gem "rack-cors"

# Windows does not include zoneinfo files, so bundle the tzinfo-data gem
gem "tzinfo-data", platforms: %i[ windows jruby ]

# Use the database-backed adapters for Rails.cache, Active Job and Action Cable
gem "solid_cache"
gem "solid_queue"
# #232 Phase 0: DB-backed Action-Cable-Adapter (laeuft auf der primary-DB,
# kein Redis, keine separate cable-DB) — Fundament fuer Live-Updates.
gem "solid_cable"

# Reduces boot times through caching; required in config/boot.rb
gem "bootsnap", require: false

# Add HTTP asset caching/compression and X-Sendfile acceleration to Puma [https://github.com/basecamp/thruster/]
gem "thruster", require: false

# Use Active Storage variants [https://guides.rubyonrails.org/active_storage_overview.html#transforming-images]
gem "image_processing", "~> 2.0"
# image_processing 2.0 bringt kein Backend mehr mit — vips explizit
# (ActiveStorage-Variants; libvips ist eh System-Requirement, s. README).
gem "ruby-vips"

# Phase 3: Gmail-Integration & verschlüsselte OAuth-Token-Speicherung
gem "google-apis-gmail_v1"
gem "signet"
gem "lockbox"

group :development, :test do
  # See https://guides.rubyonrails.org/debugging_rails_applications.html#debugging-with-the-debug-gem
  gem "debug", platforms: %i[ mri windows ], require: "debug/prelude"

  # Audits gems for known security defects (use config/bundler-audit.yml to ignore issues)
  gem "bundler-audit", require: false

  # Static analysis for security vulnerabilities [https://brakemanscanner.org/]
  gem "brakeman", require: false

  # Omakase Ruby styling [https://github.com/rails/rubocop-rails-omakase/]
  gem "rubocop-rails-omakase", require: false

  # Test coverage reporting
  gem "simplecov", require: false

  # #206 Phase 1: System-Tests fuer Stimulus-Controller. Cuprite faehrt
  # headless Chromium via CDP (kein Selenium-Server, kein chromedriver).
  gem "capybara"
  gem "cuprite"
end

group :development do
  # Use console on exceptions pages [https://github.com/rails/web-console]
  gem "web-console"
end
