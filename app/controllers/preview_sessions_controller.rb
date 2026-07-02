# #602 S3: „Als X ansehen" — Admin startet/beendet die Read-only-
# Vorschau der Sicht eines anderen Nutzers (Session-Flag; Mechanik in
# ApplicationController). Das beste Werkzeug, um Freigaben zu VERSTEHEN
# statt zu raten.
class PreviewSessionsController < ApplicationController
  # Beenden muss IMMER gehen — auch wenn der Vorschau-Nutzer selbst
  # keine Actor-Capability hätte (das Gate liefe sonst gegen ihn).
  skip_before_action :enforce_access_gate, only: :destroy

  def create
    unless real_actor&.admin?
      raise AccessGate::Unauthorized, "Nur Admins können die Vorschau nutzen."
    end
    user = HumanActor.active.find(params[:id])
    if user.id == real_actor.id
      redirect_to settings_users_path, alert: "Das ist Deine eigene Sicht." and return
    end
    session[:preview_actor_id] = user.id
    redirect_to dashboard_path, notice: "Vorschau: Du siehst miolimOS jetzt als #{user.name} (nur lesen)."
  end

  def destroy
    session.delete(:preview_actor_id)
    redirect_to settings_users_path, notice: "Vorschau beendet."
  end

  private

  def controller_resource_type = "Actor"
end
