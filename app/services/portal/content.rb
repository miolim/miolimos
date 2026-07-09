# #536: die EINE Quelle der Portal-Inhalte — von Portal::BaseController
# (live) UND PortalExporter (statischer Export) genutzt, damit Übergabe-
# Artefakt und eingeloggte Sicht nie auseinanderlaufen.
module Portal
  class Content
    # Kuratierte Meilensteine des Projekts in Projekt-Reihenfolge —
    # nur veröffentlichte (Entwürfe NIE nach außen).
    def self.milestones(topic)
      topic.tasks
           .where(client_milestone: true)
           .where.not(published_at: nil)
           .merge(TaskTopic.order(:position))
    end

    # Freigegebene, eingefrorene Dokument-Stände des Projekts. #926: die
    # Artefakt-Schicht ist polymorph (Anschreiben + Rechnungen) — je Typ
    # ein Query über die zugehörige printable-Tabelle, gemischt sortiert.
    def self.shared_artifacts(topic)
      shared = DocumentArtifact.where(shared_with_client: true)
      ids = shared.where(printable_type: "Document",
                         printable_id: Document.where(topic_id: topic.id).select(:id)).ids +
            shared.where(printable_type: "Invoice",
                         printable_id: Invoice.where(topic_id: topic.id).select(:id)).ids
      DocumentArtifact.where(id: ids).order(created_at: :desc)
    end

    # #573: freigegebene Termine/Ereignisse des Projekts.
    def self.events(topic)
      Event.where(topic_id: topic.id).for_portal.order(:starts_at)
    end

    # Portal-Thread des Projekts (chronologisch).
    def self.messages(topic)
      PortalMessage.joins(:communication_topics)
                   .where(communication_topics: { topic_id: topic.id })
                   .where(portal_visible: true)
                   .order(:created_at)
    end
  end
end
