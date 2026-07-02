class Settings::TemplatesController < Settings::BaseController
  # #613: Einstellungen sind ein Blade-Stack — die alte Reiter-URL
  # leitet auf den Stack mit geöffnetem Bereichs-Blade.
  def index
    redirect_to settings_path(stack: "list:settings,settings:templates")
  end

  private

  # Vorlagen sind Topic-Records mit template: true → Topic-Capability.
  def controller_resource_type
    "Topic"
  end
end
