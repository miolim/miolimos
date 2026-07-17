class SessionsController < ActionController::Base
  layout "auth"

  # #209: CSRF-Verification fuer den Login-POST ausgeschaltet. In Prod
  # tritt regelmaessig `Can't verify CSRF token authenticity` auf, wenn
  # ein Browser nach laengerer Pause oder nach einem Puma-Restart die
  # Login-Seite aufruft und das Token nicht mehr zur aktuellen Session
  # passt — Resultat: 422, Hans muss reloaden, dann klappt es. Die
  # Schutzwirkung von CSRF beim Login ist minimal: die Form verlangt
  # ohnehin Email+Passwort, und die Action faehrt sofort `reset_session`,
  # bevor sie session[:actor_id] setzt. Login-CSRF (Angreifer logged
  # Opfer in eigene Account ein) ist fuer ein privates Knowledge-Tool
  # ein nicht-relevantes Bedrohungsszenario.
  # #1051: verify_otp aus demselben Grund — der Schritt verlangt einen
  # frischen TOTP-Code, CSRF hat hier nichts zu schuetzen.
  skip_before_action :verify_authenticity_token, only: [:create, :verify_otp]

  # #1051: Brute-Force-Bremse auf beiden Login-Schritten (Rails-8-eigenes
  # rate_limit). 10 Versuche / 3 Minuten pro Client-IP reichen fuer jeden
  # Tippfehler-Menschen und wuergen Passwort-/Code-Raten ab. Hinter
  # cloudflared liefert remote_ip die echte Client-IP (XFF vom trusted
  # 127.0.0.1-Proxy-Hop).
  # #1055: expliziter MemoryStore statt Rails.cache — der Default-Store
  # ist im Test-Env ein :null_store (Bremse wäre ungetestet) und in Prod
  # der File-Store; bei Single-Puma ist der Prozess-Speicher gleichwertig
  # (Zaehler ueberleben keinen Restart — fuer eine Login-Bremse ok).
  RATE_LIMIT_STORE = ActiveSupport::Cache::MemoryStore.new
  rate_limit to: 10, within: 3.minutes, only: [:create, :verify_otp],
             store: RATE_LIMIT_STORE,
             with: -> { redirect_to login_path, alert: t("sessions.rate_limited") }

  # #1051: Der halb-authentifizierte Zustand (Passwort ok, Code fehlt)
  # verfaellt nach 5 Minuten — danach beginnt der Login von vorn.
  OTP_STEP_TTL = 5.minutes

  def new
    # #806: jungfräuliche Instanz (kein menschlicher Nutzer) → erst das
    # First-Run-Onboarding, das den ersten Admin anlegt.
    return redirect_to setup_path unless HumanActor.exists?
    # `no-store` verhindert, dass Browser die Login-Seite im bfcache
    # halten — eine zweite Verteidigungslinie zusaetzlich zum Skip oben.
    response.headers["Cache-Control"] = "no-store"
  end

  def create
    actor = HumanActor.find_by(email: params[:email].to_s.downcase.strip)
    if actor&.authenticate(params[:password]) && actor.active?
      if actor.otp_enabled?
        # #1051: Passwort stimmt, aber noch KEIN Login — nur der
        # Zwischenzustand wandert in die (frische) Session. return_to
        # ueberlebt den reset, damit der Deep-Link nach dem Code greift.
        return_to = session[:return_to]
        reset_session
        session[:otp_pending_actor_id] = actor.id
        session[:otp_pending_until]    = OTP_STEP_TTL.from_now.to_i
        session[:return_to]            = return_to if return_to
        redirect_to login_otp_path
      else
        finish_login(actor)
      end
    else
      flash.now[:alert] = t("sessions.invalid_credentials")
      render :new, status: :unauthorized
    end
  end

  # #1051: Schritt 2 — Code-Abfrage (TOTP oder Recovery-Code).
  def otp
    return redirect_to login_path unless otp_pending_actor
    response.headers["Cache-Control"] = "no-store"
  end

  def verify_otp
    actor = otp_pending_actor
    return redirect_to login_path unless actor
    code = params[:code].to_s
    if actor.verify_otp_code!(code) || actor.verify_otp_recovery_code!(code)
      finish_login(actor)
    else
      flash.now[:alert] = t("sessions.invalid_otp")
      render :otp, status: :unauthorized
    end
  end

  def destroy
    reset_session
    redirect_to login_path, notice: t("sessions.logged_out")
  end

  private

  # #342 (Hans, 2026-05-24): "Angemeldet"-Notice raus — der User sieht
  # sofort sein Dashboard, wozu ein extra Banner. #1051: return_to VOR dem
  # reset_session sichern — vorher wurde es vom Reset geschluckt und der
  # Deep-Link-Redirect lief ins Leere.
  def finish_login(actor)
    return_to = session[:return_to]
    reset_session
    session[:actor_id] = actor.id
    redirect_to(return_to || dashboard_path)
  end

  def otp_pending_actor
    return nil unless session[:otp_pending_actor_id]
    return nil if session[:otp_pending_until].to_i < Time.current.to_i
    actor = HumanActor.find_by(id: session[:otp_pending_actor_id])
    actor if actor&.active? && actor.otp_enabled?
  end
end
