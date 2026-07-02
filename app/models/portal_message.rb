# #536 P3: Nachricht im Portal-Projekt-Thread (STI auf Communication, wie
# Email). Kunde schreibt im Portal → inbound + portal_visible ab Entstehung;
# Hans' Antwort aus miolimOS → outbound + portal_visible beim Senden.
# Die Projekt-Zuordnung läuft wie überall über CommunicationTopic.
class PortalMessage < Communication
  scope :for_portal, -> { where(portal_visible: true).order(:created_at) }

  # Anzeigename im Portal: Kunde sieht „Sie" vs. Absender-Name.
  def from_customer? = inbound?
end
