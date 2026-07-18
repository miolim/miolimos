require "securerandom"
require "socket"
require "cgi"

namespace :gmail do
  desc "OAuth-Flow: öffnet den Authorize-Link, fängt den Callback auf 127.0.0.1:PORT und legt den OauthCredential an"
  task setup: :environment do
    actor_email = prompt("HumanActor-E-Mail (owner dieser Credential): ")
    actor = HumanActor.find_by(email: actor_email) or abort "Kein HumanActor mit #{actor_email}"

    client_id, client_secret = load_google_oauth_credentials

    # Loopback-Server binden (Google akzeptiert jede 127.0.0.1:*-URL für
    # Desktop-App-Clients ohne Registrierung). #1057 (aus immoos #989): fester
    # Port via GMAIL_SETUP_PORT, damit man den SSH-Tunnel VORHER aufsetzen kann
    # (sonst kennt man den Zufallsport erst nach dem Start).
    fixed  = ENV["GMAIL_SETUP_PORT"].to_i
    server = fixed > 0 ? TCPServer.new("127.0.0.1", fixed) : TCPServer.new("127.0.0.1", 0)
    port   = server.addr[1]
    redirect_uri = "http://127.0.0.1:#{port}/callback"
    state = SecureRandom.hex(16)

    scopes = [
      "https://www.googleapis.com/auth/gmail.readonly",
      "https://www.googleapis.com/auth/userinfo.email"
    ]

    client = Signet::OAuth2::Client.new(
      client_id:            client_id,
      client_secret:        client_secret,
      authorization_uri:    "https://accounts.google.com/o/oauth2/auth",
      token_credential_uri: "https://oauth2.googleapis.com/token",
      scope:                scopes,
      redirect_uri:         redirect_uri,
      state:                state,
      additional_parameters: { "access_type" => "offline", "prompt" => "consent" }
    )

    puts
    puts "── miolimOS Gmail Setup ────────────────────────────────────────────"
    puts "Öffne diese URL im Browser (falls Du auf einem Server ohne Browser"
    puts "bist: SSH-Tunnel mit  ssh -L #{port}:127.0.0.1:#{port} user@server"
    puts "und den Browser auf Deinem Laptop nutzen):"
    puts
    puts client.authorization_uri.to_s
    puts
    puts "Warte auf Callback auf http://127.0.0.1:#{port}/callback …"
    puts "(Strg-C bricht ab.)"

    code = wait_for_callback(server, expected_state: state)
    server.close

    abort "Kein Code empfangen." unless code

    client.code = code
    client.fetch_access_token!

    # Mail-Adresse des authorisierten Accounts ermitteln
    profile_svc = Google::Apis::GmailV1::GmailService.new
    profile_svc.authorization = client
    profile = profile_svc.get_user_profile("me")

    label = prompt("Label (optional, z.B. 'Arbeit'): ").presence

    cred = OauthCredential.find_or_initialize_by(email_address: profile.email_address)
    cred.assign_attributes(
      actor:         actor,
      provider:      "google",
      access_token:  client.access_token,
      refresh_token: client.refresh_token,
      expires_at:    Time.at(client.expires_at.to_i),
      scopes:        scopes,
      label:         label,
      active:        true
    )
    cred.save!

    puts
    puts "✓ OauthCredential gespeichert: #{cred.email_address} (actor: #{actor.name})"
  end

  desc "Inkrementeller Sync aller aktiven Credentials — oder nur einer per [email]"
  task :sync, [:email] => :environment do |_, args|
    creds = args[:email].present? ? OauthCredential.for_email(args[:email]) : OauthCredential.active
    run_sync(creds) { |c| GmailSync.sync(c) }
  end

  desc "Vollständiger Reimport für eine Credential (per email)"
  task :full_sync, [:email] => :environment do |_, args|
    email = args[:email] or abort "usage: rake gmail:full_sync[email]"
    creds = OauthCredential.for_email(email)
    run_sync(creds) { |c| GmailSync.full_sync(c) }
  end
end

# ─── Rake-Helper ─────────────────────────────────────────────────────────────

def prompt(text)
  print text
  STDIN.gets.to_s.chomp
end

def load_google_oauth_credentials
  id = ENV["GOOGLE_OAUTH_CLIENT_ID"] ||
       Rails.application.credentials.dig(:google, :oauth_client_id) or
       abort "GOOGLE_OAUTH_CLIENT_ID fehlt (ENV oder credentials[:google][:oauth_client_id])"
  secret = ENV["GOOGLE_OAUTH_CLIENT_SECRET"] ||
           Rails.application.credentials.dig(:google, :oauth_client_secret) or
           abort "GOOGLE_OAUTH_CLIENT_SECRET fehlt"
  [id, secret]
end

# Liest EINEN HTTP-Request vom Socket, extrahiert ?code=…&state=… aus der
# Request-Line, vergleicht state, schickt ein kleines HTML zurück und gibt den
# Code zurück. Minimal-Parser — reicht für genau diesen Einmal-Use-Case.
def wait_for_callback(server, expected_state:, timeout: 300)
  deadline = Time.now + timeout

  loop do
    abort "Timeout beim Warten auf OAuth-Callback." if Time.now > deadline

    ready = IO.select([server], nil, nil, 1)
    next unless ready

    client = server.accept
    request_line = client.gets.to_s
    # Drain headers
    while (line = client.gets) && line.strip != ""; end

    path_query = request_line.split(" ")[1].to_s
    params = {}
    if path_query.include?("?")
      path_query.split("?", 2).last.split("&").each do |pair|
        k, v = pair.split("=", 2)
        params[CGI.unescape(k.to_s)] = CGI.unescape(v.to_s)
      end
    end

    code    = params["code"]
    state   = params["state"]
    error   = params["error"]

    body =
      if error
        oauth_callback_html("Fehler: #{error}", "Du kannst dieses Fenster schließen.")
      elsif state != expected_state
        oauth_callback_html("State-Mismatch", "Bitte Setup neu starten.")
      elsif code
        oauth_callback_html("miolimOS: Autorisierung erhalten ✓", "Du kannst dieses Fenster schließen und zum Terminal zurückkehren.")
      else
        oauth_callback_html("Kein Code empfangen", "Bitte Setup neu starten.")
      end

    client.write(
      "HTTP/1.1 200 OK\r\n" \
      "Content-Type: text/html; charset=utf-8\r\n" \
      "Content-Length: #{body.bytesize}\r\n" \
      "Connection: close\r\n\r\n" \
      "#{body}"
    )
    client.close

    return code if code && state == expected_state && !error
    return nil  if error || (state && state != expected_state)
  end
end

def oauth_callback_html(title, message)
  <<~HTML
    <!doctype html>
    <html lang="de"><head><meta charset="utf-8"><title>#{CGI.escapeHTML(title)}</title>
    <style>body{font-family:system-ui,sans-serif;padding:2em;max-width:40em;margin:auto}
    h1{font-size:1.2em;margin-bottom:.5em}
    p{color:#555}</style></head>
    <body><h1>#{CGI.escapeHTML(title)}</h1><p>#{CGI.escapeHTML(message)}</p></body></html>
  HTML
end

def run_sync(creds)
  abort "Keine passende Credential" if creds.empty?
  creds.find_each do |cred|
    puts "Syncing #{cred.email_address}…"
    result = yield(cred)
    puts "  → #{result}"
  rescue => e
    puts "  ✗ #{e.class}: #{e.message}"
  end
end
