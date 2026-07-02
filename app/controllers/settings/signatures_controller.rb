# #547 (Hans, 2026-06-08): Unterschriftsbild des aktuellen Users verwalten.
# Als Data-URI am Actor gespeichert (klein, selbst-enthalten fürs PDF).
class Settings::SignaturesController < Settings::BaseController
  MAX_BYTES = 1.megabyte

  # #613: Einstellungen sind ein Blade-Stack — die alte Reiter-URL
  # leitet auf den Stack mit geöffnetem Bereichs-Blade.
  def show
    redirect_to settings_path(stack: "list:settings,settings:signature")
  end

  def update
    file = params[:signature]
    unless file.respond_to?(:read)
      redirect_to settings_signature_path, alert: "Keine Datei gewählt." and return
    end
    type = file.content_type.to_s
    unless type.start_with?("image/")
      redirect_to settings_signature_path, alert: "Bitte ein Bild hochladen (PNG/JPG)." and return
    end
    data = file.read
    if data.bytesize > MAX_BYTES
      redirect_to settings_signature_path, alert: "Bild zu groß (max. 1 MB)." and return
    end
    current_actor.update!(signature_image: "data:#{type};base64,#{Base64.strict_encode64(data)}")
    redirect_to settings_signature_path, notice: "Unterschrift gespeichert."
  end

  def destroy
    current_actor.update!(signature_image: nil)
    redirect_to settings_signature_path, notice: "Unterschrift entfernt."
  end

  private

  def controller_resource_type = "Actor"

  def controller_action_to_capability
    %w[update destroy].include?(action_name) ? "update" : "read"
  end
end
