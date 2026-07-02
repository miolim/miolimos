# #536 P2: die Inhaltsseiten des Portals. Alle Queries kommen aus den hart
# gescopten Helfern der BaseController — hier wird nur gerendert.
module Portal
  class PagesController < BaseController
    # Startseite: Projektname, Stand, zuletzt aktualisiert.
    def home
      @milestones = project_milestones.to_a
      @artifacts  = shared_artifacts.includes(document: :topic).limit(5).to_a
      @messages   = portal_messages.last(3)
      # „Zuletzt aktualisiert": jüngstes Ereignis über alle geteilten Inhalte.
      @updated_at = [
        @milestones.map(&:updated_at).max,
        @artifacts.map(&:created_at).max,
        @messages.map(&:created_at).max
      ].compact.max
    end

    def roadmap
      @milestones = project_milestones.to_a
    end

    # Termine: freigegebene Ereignisse/Termine (#573) + Meilenstein-Datums.
    def termine
      @dated  = project_milestones.where.not(due_date: nil).order(:due_date).to_a
      @events = Portal::Content.events(current_project).to_a
    end

    def dokumente
      @artifacts = shared_artifacts.includes(document: :topic).to_a
    end

    # PDF eines freigegebenen Artefakts — strikt über shared_artifacts
    # gescoped (fremde/ungeteilte IDs laufen in RecordNotFound → 404).
    def artifact
      artifact = shared_artifacts.find(params[:id])
      send_data artifact.pdf, type: "application/pdf",
        disposition: "inline",
        filename: "#{artifact.document.display_name.presence || "dokument"}-#{artifact.id}.pdf"
    end

    def nachrichten
      @messages = portal_messages.to_a
    end

    # Kunde schreibt in den Projekt-Thread.
    def create_message
      body = params[:body].to_s.strip
      if body.blank?
        redirect_to portal_nachrichten_path, alert: "Bitte eine Nachricht eingeben." and return
      end
      message = PortalMessage.create!(
        direction:      :inbound,
        subject:        "Portal-Nachricht von #{current_access.email}",
        body:           body,
        sent_at:        Time.current,
        portal_visible: true,
        external_id:    "portal-#{SecureRandom.uuid}",
        participants:   { "from" => [ current_access.email ] }
      )
      CommunicationTopic.create!(communication: message, topic: current_project)
      PortalNotifier.customer_message(message, current_access)
      redirect_to portal_nachrichten_path, notice: "Nachricht gesendet."
    end
  end
end
