class Settings::BaseController < ApplicationController
  layout "application"

  private

  # #1675: Das Recht „Actor" hat laut Rechtematrix JEDER Mensch (HumanActors
  # bekommen Vollrechte, CapabilityDefaults) — es taugt also nicht als Grenze
  # für Verwaltungs-Bereiche. Benutzer und Agenten verwalten ist Admin-Sache:
  # Ein Agenten-Token sieht alles (Agenten sind von der Sichtbarkeit aus #602
  # ausgenommen), und wer fremde E-Mail-Adressen ändern darf, übernimmt per
  # „Passwort vergessen" jedes Konto. Bewusst current_actor: In der Vorschau
  # „als X ansehen" (#602) sieht der Admin genau, was X sähe.
  def require_admin!
    return if current_actor&.admin?
    raise AccessGate::Unauthorized, t("settings.admin_only")
  end

  # Default Gate: "Actor"-Capability deckt Users + Agents ab; Kind-Controller
  # können das überschreiben (Accounts = OauthCredential, Teams = Team).
  def controller_resource_type
    "Actor"
  end
end
