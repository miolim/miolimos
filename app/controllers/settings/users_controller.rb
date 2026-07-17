class Settings::UsersController < Settings::BaseController
  before_action :set_user, only: [:edit, :update, :destroy, :reset_two_factor]

  # #613: Einstellungen sind ein Blade-Stack — die alte Reiter-URL
  # leitet auf den Stack mit geöffnetem Bereichs-Blade.
  def index
    redirect_to settings_path(stack: "list:settings,settings:users")
  end

  # #613 St.2: Einzelfenster abgelöst — als Blade im Einstellungs-Stack.
  def new
    redirect_to settings_path(stack: "list:settings,settings:users,settingssub:users:new")
  end

  def create
    @user = HumanActor.new(user_params)
    if @user.save
      # #927: Ein neuer Benutzer bekam bisher KEINE Capabilities → beim ersten
      # Login „… is not allowed to read Task". HumanActors kriegen laut
      # Rechtematrix Vollrechte (CapabilityDefaults); genau das hier vergeben,
      # damit der Nutzer die App direkt verwenden kann.
      CapabilityDefaults.grant_full!(@user)
      redirect_to settings_users_path, notice: "Benutzer '#{@user.name}' angelegt."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    redirect_to settings_path(stack: "list:settings,settings:users,settingssub:users:#{@user.id}:edit")
  end

  def update
    attrs = user_params
    attrs.delete(:password) if attrs[:password].blank?  # leer = nicht ändern
    if @user.update(attrs)
      redirect_to settings_users_path, notice: "Benutzer gespeichert."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # #1051: Admin-Rettungsweg bei verlorenem zweiten Faktor — setzt 2FA des
  # Nutzers komplett zurück (Secret, Recovery-Codes). Nur Admins; die
  # eigene 2FA verwaltet man unter Einstellungen → Sicherheit.
  def reset_two_factor
    unless current_actor&.admin?
      redirect_to settings_users_path, alert: t("settings.two_factor.admin_only")
      return
    end
    @user.disable_otp!
    redirect_to settings_path(stack: "list:settings,settings:users,settingssub:users:#{@user.id}:edit"),
                notice: t("settings.two_factor.reset_done", name: @user.name)
  end

  def destroy
    if @user == current_actor
      redirect_to settings_users_path, alert: "Du kannst Dich nicht selbst löschen."
      return
    end
    @user.destroy!
    redirect_to settings_users_path, notice: "Benutzer gelöscht."
  end

  private

  def set_user
    @user = HumanActor.find(params[:id])
  end

  def user_params
    permitted = [:name, :email, :password, :active]
    # #602 S1: Rolle darf nur ein Admin vergeben — sonst könnte sich ein
    # Mitglied selbst zum Admin machen.
    permitted << :role if current_actor&.admin?
    params.require(:human_actor).permit(*permitted)
  end
end
