class Settings::BaseController < ApplicationController
  layout "application"

  private

  # Default Gate: "Actor"-Capability deckt Users + Agents ab; Kind-Controller
  # können das überschreiben (Accounts = OauthCredential, Teams = Team).
  def controller_resource_type
    "Actor"
  end
end
