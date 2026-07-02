# #536: interne Verwaltung der Portal-Zugänge eines Projekts (Topic-Blade).
# #570 (Hans): Anlegen und Link-Versand sind ENTKOPPELT — die Mail geht erst
# über den gesonderten Senden-Button raus (Hans entscheidet den Zeitpunkt).
# Deaktivieren ist der Kill-Switch (Sessions sind sofort wertlos).
class PortalAccessesController < ApplicationController
  def create
    topic = find_topic
    access = PortalAccess.new(topic: topic, email: params[:email],
                              knowledge_item_uuid: topic.customer_uuid)
    if access.save
      render_section(topic, toast: "Zugang angelegt — Link über den Senden-Knopf verschicken.")
    else
      render_section(topic, toast: access.errors.full_messages.to_sentence)
    end
  end

  # #570: Magic-Link explizit verschicken (auch erneut, z.B. nach Ablauf).
  def send_link
    access = PortalAccess.find(params[:id])
    PortalMailer.magic_link(access).deliver_later
    render_section(access.topic, toast: "Anmelde-Link an #{access.email} verschickt.")
  end

  def update
    access = PortalAccess.find(params[:id])
    access.update!(active: params[:active] == "1")
    render_section(access.topic)
  end

  # #536 P4: statischer Export (Übergabe) — versionierte ZIP mit denselben
  # Inhalten, die der eingeloggte Kunde sieht.
  def export
    topic = find_topic
    send_data PortalExporter.zip(topic),
      type: "application/zip", disposition: "attachment",
      filename: PortalExporter.filename(topic)
  end

  private

  # Topic#to_param ist der Slug — die verschachtelten Routen liefern ihn
  # als :topic_id (die Nested-Deklaration hat kein param: :slug).
  def find_topic
    Topic.find_by!(slug: params[:topic_id])
  end


  def render_section(topic, toast: nil)
    streams = [ turbo_stream.replace("topic_portal_accesses_#{topic.id}",
      partial: "topics/portal_accesses", locals: { topic: topic }) ]
    streams << helpers.toast_stream(message: toast) if toast
    render turbo_stream: streams
  end

  def controller_resource_type = "Topic"
  def controller_action_to_capability = "update"
end
