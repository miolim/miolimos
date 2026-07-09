# #536: Export-Bewusstsein der Portal-Views. Im Live-Betrieb normale Pfade;
# im statischen Export (@export = true) relative Dateinamen — dieselben
# Templates erzeugen beide Welten.
module PortalHelper
  def portal_href(live_path, export_file)
    @export ? export_file : live_path
  end

  def portal_artifact_href(artifact)
    @export ? "dokumente/#{portal_artifact_filename(artifact)}" : portal_artifact_path(artifact)
  end

  def portal_artifact_filename(artifact)
    base = (artifact.printable.display_name.presence || "dokument-#{artifact.printable_id}")
             .gsub(/\s+/, "-").gsub(/[^\p{Alnum}\-_.]/u, "")
    "#{base}-#{artifact.id}.pdf"
  end

  # Projekt-Kontext: live aus der Session, im Export gesetzt.
  def portal_topic
    @export ? @export_topic : current_access&.topic
  end
end
