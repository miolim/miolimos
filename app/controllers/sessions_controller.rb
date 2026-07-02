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
  skip_before_action :verify_authenticity_token, only: :create

  def new
    # `no-store` verhindert, dass Browser die Login-Seite im bfcache
    # halten — eine zweite Verteidigungslinie zusaetzlich zum Skip oben.
    response.headers["Cache-Control"] = "no-store"
  end

  def create
    actor = HumanActor.find_by(email: params[:email].to_s.downcase.strip)
    if actor&.authenticate(params[:password]) && actor.active?
      reset_session
      session[:actor_id] = actor.id
      # #342 (Hans, 2026-05-24): "Angemeldet"-Notice raus — der User
      # sieht sofort sein Dashboard, wozu ein extra Banner. Auf Mobile
      # blieb das Banner sonst bis zum naechsten Refresh haengen.
      redirect_to(session.delete(:return_to) || dashboard_path)
    else
      flash.now[:alert] = t("sessions.invalid_credentials")
      render :new, status: :unauthorized
    end
  end

  def destroy
    reset_session
    redirect_to login_path, notice: t("sessions.logged_out")
  end
end
