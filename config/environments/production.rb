require "active_support/core_ext/integer/time"

Rails.application.configure do
  # Settings specified here will take precedence over those in config/application.rb.

  # Code is not reloaded between requests.
  config.enable_reloading = false

  # Eager load code on boot for better performance and memory savings (ignored by Rake tasks).
  config.eager_load = true

  # Full error reports are disabled.
  config.consider_all_requests_local = false

  # Turn on fragment caching in view templates.
  config.action_controller.perform_caching = true

  # Cache assets for far-future expiry since they are all digest stamped.
  config.public_file_server.headers = { "cache-control" => "public, max-age=#{1.year.to_i}" }

  # Enable serving of images, stylesheets, and JavaScripts from an asset server.
  # config.asset_host = "http://assets.example.com"

  # Store uploaded files on the local file system (see config/storage.yml for options).
  config.active_storage.service = :local

  # #1060: SSL-Zwang haengt am Protokoll. Default bleibt https (Prod hinter
  # dem cloudflared-Tunnel, der TLS terminiert). Fuer eine lokale Einzelplatz-
  # Installation ohne Reverse-Proxy (docker compose, `MIOLIMOS_PROTOCOL=http`)
  # muss der Redirect aus — sonst schickt die App den Browser von
  # http://localhost:3000 auf ein https, das dort niemand bedient.
  ssl = ENV.fetch("MIOLIMOS_PROTOCOL", "https") == "https"

  # Assume all access to the app is happening through a SSL-terminating reverse proxy.
  config.assume_ssl = ssl

  # Force all access to the app over SSL, use Strict-Transport-Security, and use secure cookies.
  config.force_ssl = ssl

  # Skip http-to-https redirect for the default health check endpoint.
  # config.ssl_options = { redirect: { exclude: ->(request) { request.path == "/up" } } }

  # Log to STDOUT with the current request id as a default log tag.
  config.log_tags = [ :request_id ]
  config.logger   = ActiveSupport::TaggedLogging.logger(STDOUT)

  # Change to "debug" to log everything (including potentially personally-identifiable information!).
  config.log_level = ENV.fetch("RAILS_LOG_LEVEL", "info")

  # Prevent health checks from clogging up the logs.
  config.silence_healthcheck_path = "/up"

  # Don't log any deprecations.
  config.active_support.report_deprecations = false

  # Replace the default in-process memory cache store with a durable alternative.
  # config.cache_store = :mem_cache_store

  # Replace the default in-process and non-durable queuing backend for Active Job.
  config.active_job.queue_adapter = :solid_queue
  config.solid_queue.connects_to = { database: { writing: :queue } }

  # #232 Phase 0: Action Cable / Live-Updates. os.miolim.de wird vom
  # cloudflared-Tunnel direkt an Puma (localhost:3007) durchgereicht —
  # kein nginx dazwischen, WebSockets traegt der Tunnel nativ. Der
  # Browser oeffnet wss://os.miolim.de/cable; Action Cable prueft den
  # Origin-Header gegen diese Liste.
  # #735: Host konfigurierbar (Self-Hosting). Default = bisheriger Prod-Host.
  # #1060: Protokoll ebenfalls — bei MIOLIMOS_PROTOCOL=http erwartet Cable
  # sonst eine https-Origin, die der Browser lokal nie sendet (WebSockets tot).
  # MIOLIMOS_CABLE_ORIGINS (kommagetrennt) ueberschreibt die Liste komplett —
  # noetig, wenn der Browser einen Port mitschickt (`http://localhost:3000`),
  # denn der gehoert in die Origin, aber nicht in MIOLIMOS_HOST (Mailer-URLs).
  config.action_cable.allowed_request_origins =
    ENV["MIOLIMOS_CABLE_ORIGINS"].to_s.split(",").map(&:strip).reject(&:empty?).presence ||
    [ "#{ENV.fetch("MIOLIMOS_PROTOCOL", "https")}://#{ENV.fetch("MIOLIMOS_HOST", "os.miolim.de")}" ]

  # #536/#570: Versand über die Gmail-API (GmailSender + Initializer
  # gmail_api_delivery). Fehler sollen knallen — ein Magic-Link, der still
  # nicht ankommt, ist schlimmer als ein sichtbarer Job-Fehler.
  config.action_mailer.delivery_method = :gmail_api
  config.action_mailer.raise_delivery_errors = true

  # Set host to be used by links generated in mailer templates.
  config.action_mailer.default_url_options = { host: ENV.fetch("MIOLIMOS_HOST", "os.miolim.de"), protocol: ENV.fetch("MIOLIMOS_PROTOCOL", "https") }

  # Specify outgoing SMTP server. Remember to add smtp/* credentials via bin/rails credentials:edit.
  # config.action_mailer.smtp_settings = {
  #   user_name: Rails.application.credentials.dig(:smtp, :user_name),
  #   password: Rails.application.credentials.dig(:smtp, :password),
  #   address: "smtp.example.com",
  #   port: 587,
  #   authentication: :plain
  # }

  # Enable locale fallbacks for I18n (makes lookups for any locale fall back to
  # the I18n.default_locale when a translation cannot be found).
  config.i18n.fallbacks = true

  # Do not dump schema after migrations.
  config.active_record.dump_schema_after_migration = false

  # Only use :id for inspections in production.
  config.active_record.attributes_for_inspect = [ :id ]

  # Enable DNS rebinding protection and other `Host` header attacks.
  # config.hosts = [
  #   "example.com",     # Allow requests from example.com
  #   /.*\.example\.com/ # Allow requests from subdomains like `www.example.com`
  # ]
  #
  # Skip DNS rebinding protection for the default health check endpoint.
  # config.host_authorization = { exclude: ->(request) { request.path == "/up" } }
end
