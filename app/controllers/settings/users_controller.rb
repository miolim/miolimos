class Settings::UsersController < Settings::BaseController
  before_action :set_user, only: [:edit, :update, :destroy, :reset_two_factor]
  # #1675: Benutzer verwalten nur Admins. Ausnahme ist das EIGENE Profil
  # (Name, E-Mail, Passwort) — das pflegt jeder selbst.
  before_action :require_admin!, unless: :eigenes_profil?

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
    # #1520 (Hans): „Passwort für andere Nutzer ändern bitte an Admin-Rechte
    # binden." Bis hierher konnte JEDER angemeldete Nutzer das Passwort jedes
    # anderen setzen — auch das eines Admins: HumanActors bekommen laut
    # Rechtematrix Vollrechte auf `Actor` (CapabilityDefaults), und der Gate
    # dieses Controllers prüft genau das. Admin-geschützt war allein die Rolle.
    #
    # Abgewiesen statt still übergangen: Ein weggeworfenes Passwortfeld sähe
    # aus, als hätte es funktioniert. Das EIGENE Passwort bleibt hier möglich
    # (die Selbstbedienung dafür steht unter Sicherheit) — gebunden ist genau
    # das, was Hans genannt hat: das Passwort ANDERER.
    if attrs[:password].present? && @user != current_actor && !current_actor&.admin?
      redirect_to settings_users_path, alert: t("settings.users.password_admin_only")
      return
    end
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
    # #1675: Wer Inhalte angelegt hat, wird nicht gelöscht. Themen tragen
    # creator_id NOT NULL — das „nullify" endete in einer Fehlerseite —, und die
    # Wartepunkte des Nutzers wären still mitgelöscht worden. Der richtige Weg
    # ist Deaktivieren: Anmeldung gesperrt, Urheberschaft bleibt.
    if @user.hinterlaesst_inhalte?
      redirect_to settings_users_path, alert: t("settings.users.delete_has_content", name: @user.name)
      return
    end
    @user.destroy!
    redirect_to settings_users_path, notice: "Benutzer gelöscht."
  end

  private

  def set_user
    @user = HumanActor.find(params[:id])
  end

  # Nur edit/update am eigenen Datensatz — nie new/create/destroy.
  def eigenes_profil?
    action_name.in?(%w[edit update]) && @user.present? && @user == current_actor
  end

  def user_params
    permitted = [:name, :email, :password]
    # #602 S1: Rolle darf nur ein Admin vergeben — sonst könnte sich ein
    # Mitglied selbst zum Admin machen. #1675: dasselbe für den Aktiv-Status.
    permitted += [:role, :active] if current_actor&.admin?
    params.require(:human_actor).permit(*permitted)
  end
end
