# #1520 (Hans): „Passwort vergessen". Bewusst OHNE Anmeldung erreichbar und
# deshalb wie SessionsController direkt auf ActionController::Base — der
# Rechte-Gate der ApplicationController-Kette hat hier keinen Actor, den er
# fragen koennte.
#
# Der Link traegt einen signierten Token (HumanActor#generates_token_for), der
# am Salz des aktuellen Passworts haengt: Ein gesetztes neues Passwort entwertet
# jeden noch offenen Link von selbst. Keine Spalte, kein Aufraeum-Job.
class PasswordResetsController < ActionController::Base
  layout "auth"

  # Wie beim Login (#209): Das CSRF-Token passt nach langer Pause oder einem
  # Puma-Neustart oft nicht mehr zur Session, und der Nutzer saehe ein 422
  # statt eines Formulars. Zu schuetzen ist hier nichts: Das Anfordern
  # verlangt eine Mail-Adresse und verraet nichts, das Setzen verlangt den
  # signierten Token aus der Mail.
  skip_before_action :verify_authenticity_token, only: [:create, :update]

  # Bremse gegen das Absuchen von Adressen und gegen Mail-Fluten an einen
  # fremden Posteingang. Eigener MemoryStore aus demselben Grund wie in
  # SessionsController (#1055): Der Default-Store ist im Test :null_store,
  # die Bremse waere ungeprueft.
  RATE_LIMIT_STORE = ActiveSupport::Cache::MemoryStore.new
  rate_limit to: 5, within: 5.minutes, only: [:create],
             store: RATE_LIMIT_STORE,
             with: -> { redirect_to new_password_reset_path, alert: t("passwords.rate_limited") }

  def new
    response.headers["Cache-Control"] = "no-store"
  end

  # Die Antwort ist IMMER dieselbe — auch bei unbekannter oder stillgelegter
  # Adresse. Sonst wuerde die Seite verraten, wer hier ein Konto hat.
  def create
    actor = HumanActor.find_by(email: params[:email].to_s.downcase.strip)
    AuthMailer.password_reset(actor).deliver_later if actor&.active?
    redirect_to login_path, notice: t("passwords.sent")
  end

  def edit
    @actor = actor_aus_token
    return weg_mit_ungueltigem_link unless @actor
    @token = params[:token].to_s
    response.headers["Cache-Control"] = "no-store"
  end

  def update
    actor = actor_aus_token
    return weg_mit_ungueltigem_link unless actor

    @actor = actor
    @token = params[:token].to_s
    neu    = params[:password].to_s
    if neu != params[:password_confirmation].to_s
      flash.now[:alert] = t("passwords.mismatch")
      return render :edit, status: :unprocessable_entity
    end

    actor.password = neu
    if actor.save
      # Kein Auto-Login: Wer 2FA eingeschaltet hat, soll auch nach dem
      # Zuruecksetzen den zweiten Faktor zeigen. Ein Link aus einer Mail darf
      # daran nicht vorbeifuehren.
      redirect_to login_path, notice: t("passwords.changed")
    else
      flash.now[:alert] = actor.errors.full_messages.to_sentence
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def actor_aus_token
    HumanActor.find_by_token_for(:password_reset, params[:token].to_s)
  end

  def weg_mit_ungueltigem_link
    redirect_to new_password_reset_path, alert: t("passwords.link_invalid")
  end
end
