class Settings::TeamsController < Settings::BaseController
  def controller_resource_type
    "Team"
  end

  # #613: Einstellungen sind ein Blade-Stack — die alte Reiter-URL
  # leitet auf den Stack mit geöffnetem Bereichs-Blade.
  def index
    redirect_to settings_path(stack: "list:settings,settings:teams")
  end
end
