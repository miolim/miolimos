require "signet/oauth_2/client"
require "securerandom"

class Settings::AccountsController < Settings::BaseController
  # #536: gmail.send für den Portal-Mail-Versand (GmailSender) — beim
  # (Neu-)Verbinden willigt Google einmal zusätzlich in den Versand ein.
  SCOPES = [
    "https://www.googleapis.com/auth/gmail.readonly",
    "https://www.googleapis.com/auth/gmail.send",
    # #573 v2: Termine in den Google-Kalender schreiben (GcalPush).
    "https://www.googleapis.com/auth/calendar.events",
    "https://www.googleapis.com/auth/userinfo.email"
  ].freeze

  # "OauthCredential" als eigener Gate-Resource-Type — damit man
  # Gmail-Accounts separat von HumanActor/AgentActor gaten kann.
  def controller_resource_type
    "OauthCredential"
  end

  # Override default action→capability mapping so custom actions hit
  # the right bucket.
  def controller_action_to_capability
    case action_name
    when "connect", "callback"  then "create"
    when "sync", "sync_policy"  then "update"
    else super
    end
  end

  # #613: Einstellungen sind ein Blade-Stack — die alte Reiter-URL
  # leitet auf den Stack mit geöffnetem Bereichs-Blade.
  def index
    redirect_to settings_path(stack: "list:settings,settings:accounts")
  end

  # #768 (Hans): globale Mail-Sync-Policy setzen — internen Team-Verkehr
  # vom Import ausschließen (an) oder einschließen (aus).
  def sync_policy
    Setting.set(Setting::SYNC_EXCLUDE_INTERNAL_KEY,
                params[:exclude_internal].to_s == "1" ? "true" : "false")
    redirect_to settings_path(stack: "list:settings,settings:accounts"),
                notice: t("settings.accounts.sync_policy_saved")
  end

  # Schritt 1: Redirect zu Google mit korrekter redirect_uri.
  def connect
    state = SecureRandom.hex(16)
    session[:oauth_state] = state
    session[:oauth_actor_id] = current_actor.id

    client = signet_client(state: state)
    redirect_to client.authorization_uri.to_s, allow_other_host: true
  rescue RuntimeError => e
    # #536: fehlende Client-Konfiguration (z.B. oauth_client_secret nicht in
    # den Rails-Credentials) soll erklären statt 500 werfen.
    redirect_to settings_accounts_path, alert: "Verbinden nicht möglich: #{e.message}"
  end

  # Schritt 2: Google ruft uns hier mit ?code=...&state=... auf.
  def callback
    if params[:error].present?
      redirect_to settings_accounts_path, alert: "Google-Fehler: #{params[:error]}"
      return
    end

    expected_state = session.delete(:oauth_state)
    actor_id       = session.delete(:oauth_actor_id)
    if expected_state.blank? || params[:state] != expected_state
      redirect_to settings_accounts_path, alert: "State-Mismatch — Flow neu starten."
      return
    end

    actor = HumanActor.find_by(id: actor_id) || current_actor
    client = signet_client
    client.code = params[:code]
    client.fetch_access_token!

    profile_svc = Google::Apis::GmailV1::GmailService.new
    profile_svc.authorization = client
    profile = profile_svc.get_user_profile("me")

    cred = OauthCredential.find_or_initialize_by(email_address: profile.email_address)
    # #574: Startdatum des kuratierten Syncs = Zeitpunkt des Verbindens —
    # der Alt-Bestand des Postfachs bleibt draußen (Label holt gezielt Älteres).
    cred.sync_since ||= Time.current
    cred.assign_attributes(
      actor:         actor,
      provider:      "google",
      access_token:  client.access_token,
      refresh_token: client.refresh_token,
      expires_at:    Time.at(client.expires_at.to_i),
      scopes:        SCOPES,
      active:        true
    )
    cred.save!

    redirect_to settings_accounts_path, notice: "Gmail-Account #{cred.email_address} verbunden."
  rescue => e
    Rails.logger.error("Gmail OAuth callback: #{e.class} #{e.message}")
    redirect_to settings_accounts_path, alert: "Verbindung fehlgeschlagen: #{e.message}"
  end

  def sync
    cred = manageable_credentials.find(params[:id])
    result = GmailSync.sync(cred)
    # #689 (Hans): Sync soll das Blade NICHT verändern. Früher redirectete
    # die Action auf einen hartkodierten Stack (list:settings,settings:accounts)
    # → der Blade-Stack wurde neu aufgebaut, Breite/Position der Card gingen
    # verloren. Jetzt nur ein Toast via Turbo-Stream — keine Navigation, das
    # Accounts-Blade bleibt unangetastet (an der Account-Tabelle ändert ein
    # Sync ohnehin nichts Sichtbares).
    respond_to do |format|
      format.turbo_stream { render turbo_stream: helpers.toast_stream(message: "Sync #{cred.email_address}: #{result}") }
      format.html { redirect_to settings_accounts_path, notice: "Sync #{cred.email_address}: #{result}" }
    end
  rescue => e
    Rails.logger.error("Gmail sync: #{e.class} #{e.message}")
    respond_to do |format|
      format.turbo_stream { render turbo_stream: helpers.toast_stream(message: "Sync fehlgeschlagen: #{e.message}") }
      format.html { redirect_to settings_accounts_path, alert: "Sync fehlgeschlagen: #{e.message}" }
    end
  end

  # #573-Folge (Hans): Ziel-Kalender für den GCal-Push pro Konto —
  # leer = Hauptkalender ("primary"). Die Kalender-ID steht in Google
  # Kalender unter Einstellungen > [Kalender] > Kalender integrieren.
  def update_settings
    cred = manageable_credentials.find(params[:id])
    cred.update!(gcal_calendar_id: params[:gcal_calendar_id].to_s.strip.presence)
    redirect_to settings_accounts_path,
                notice: "Kalender für #{cred.email_address}: #{cred.gcal_calendar_id.presence || "Hauptkalender (primary)"}"
  end

  def destroy
    cred = manageable_credentials.find(params[:id])
    email = cred.email_address
    cred.destroy!
    redirect_to settings_accounts_path, notice: "#{email} getrennt."
  end

  private

  # #602 S2: Konten verwaltet der Inhaber selbst — Admins alle. Ein
  # Member darf fremde Postfächer weder syncen noch trennen.
  def manageable_credentials
    current_actor.visibility_exempt? ? OauthCredential.all : OauthCredential.where(actor: current_actor)
  end

  def signet_client(state: nil)
    client_id     = ENV["GOOGLE_OAUTH_CLIENT_ID"]     || Rails.application.credentials.dig(:google, :oauth_client_id)
    client_secret = ENV["GOOGLE_OAUTH_CLIENT_SECRET"] || Rails.application.credentials.dig(:google, :oauth_client_secret)
    if client_id.blank? || client_secret.blank?
      missing = client_id.blank? ? "oauth_client_id" : "oauth_client_secret"
      raise "Google-Client-Konfiguration unvollständig — #{missing} fehlt " \
            "(bin/rails credentials:edit → google: #{missing}: …, Wert steht in der " \
            "Google Cloud Console unter APIs & Dienste → Anmeldedaten)"
    end

    Signet::OAuth2::Client.new(
      client_id:            client_id,
      client_secret:        client_secret,
      authorization_uri:    "https://accounts.google.com/o/oauth2/auth",
      token_credential_uri: "https://oauth2.googleapis.com/token",
      scope:                SCOPES,
      redirect_uri:         callback_settings_accounts_url,
      state:                state,
      additional_parameters: { "access_type" => "offline", "prompt" => "consent" }
    )
  end
end
