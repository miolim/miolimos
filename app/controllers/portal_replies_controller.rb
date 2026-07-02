# #536 P3: Hans' Antwort in den Portal-Thread — aus der Communication-Detail
# einer Portal-Nachricht. Erzeugt eine outbound PortalMessage am selben
# Projekt + Mail-Ping an die aktiven Portal-Zugänge.
class PortalRepliesController < ApplicationController
  def create
    source = Communication.find(params[:communication_id])
    topic  = source.topics.first
    body   = params[:body].to_s.strip
    if topic.nil? || body.blank?
      redirect_back fallback_location: communications_path,
        alert: topic.nil? ? "Die Nachricht hängt an keinem Projekt." : "Bitte eine Antwort eingeben."
      return
    end
    reply = PortalMessage.create!(
      direction: :outbound, subject: "Re: #{source.subject}".truncate(200),
      body: body, sent_at: Time.current, portal_visible: true,
      external_id: "portal-#{SecureRandom.uuid}"
    )
    CommunicationTopic.create!(communication: reply, topic: topic)
    PortalNotifier.reply_posted(topic)
    redirect_back fallback_location: communications_path,
      notice: "Antwort steht im Portal — der Kunde bekommt einen Mail-Hinweis."
  end

  private

  def controller_resource_type = "Communication"
  def controller_action_to_capability = "update"
end
