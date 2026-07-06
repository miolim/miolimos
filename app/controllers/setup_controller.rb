# #806: First-Run-Onboarding. Solange kein menschlicher Nutzer existiert,
# ist die Instanz „unkonfiguriert" — dieser Controller zeigt genau dann
# einen Einrichtungs-Screen, der den ersten Admin anlegt (statt des alten
# Wegs über db:seed + ENV-Variablen). Sobald ein HumanActor existiert,
# sind beide Actions hart gesperrt (Redirect zum Login) — der Screen kann
# also nie zur Hintertür werden.
class SetupController < ActionController::Base
  layout "auth"

  # #818: Doppel-Submit-Race beim Onboarding. Das Auth-Layout lädt kein JS
  # (kein Turbo-Klickschutz); zwei schnelle Submits → der erste legt den
  # Admin an und rotiert via reset_session die Session → der CSRF-Token des
  # zweiten ist ungültig → 422 als sichtbare Antwort, obwohl alles klappte.
  # Statt 422: freundlich dorthin leiten, wo es weitergeht.
  rescue_from ActionController::InvalidAuthenticityToken do
    redirect_to HumanActor.exists? ? login_path : setup_path
  end

  before_action :block_when_configured

  def new
    @actor = HumanActor.new
  end

  def create
    @actor = HumanActor.new(setup_params.merge(role: :admin, active: true))
    # has_secure_password läuft hier mit validations: false — Presence und
    # Confirmation müssen wir selbst prüfen, sonst entstünde ein Admin ohne
    # Passwort (Instanz wäre dauerhaft ausgesperrt: Setup zu, Login unmöglich).
    if setup_params[:password].blank?
      @actor.errors.add(:password, :blank)
    elsif setup_params[:password] != setup_params[:password_confirmation]
      @actor.errors.add(:password_confirmation, t("setup.password_mismatch"))
    end
    if @actor.errors.none? && @actor.save
      # Erster Admin bekommt die Standard-Vollrechte (gleiche Matrix wie
      # Seeds/capabilities:sync) und ist direkt angemeldet.
      CapabilityDefaults.grant_full!(@actor)
      reset_session
      session[:actor_id] = @actor.id
      redirect_to dashboard_path, notice: t("setup.created")
    else
      render :new, status: :unprocessable_entity
    end
  end

  private

  def block_when_configured
    redirect_to login_path if HumanActor.exists?
  end

  def setup_params
    params.require(:human_actor).permit(:name, :email, :password, :password_confirmation)
  end
end
