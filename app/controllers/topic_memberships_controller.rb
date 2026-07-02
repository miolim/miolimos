# #602 S1: Verwaltung der Topic-Mitglieder + Topic-Sichtbarkeit aus dem
# Eigenschaften-Blade (Muster: PortalAccessesController). Mitglieder
# sehen das Topic samt Inhalten (visible_to-Scopes); die Mitglieds-Rolle
# (viewer/editor/owner) wird in S1 gespeichert, aber noch nicht als
# Schreibrecht ausgewertet.
class TopicMembershipsController < ApplicationController
  # #602 S2: Mitglieder/Sichtbarkeit verwalten darf nur, wer das Topic
  # auch verantwortet — Admin oder Mitglied mit Rolle owner. Sonst könnte
  # ein bloßer Betrachter sich selbst hochstufen oder Fremde einladen.
  before_action :require_topic_stewardship

  def create
    topic = find_topic
    actor = HumanActor.find(params[:actor_id])
    membership = TopicMembership.new(topic: topic, actor: actor,
                                     role: params[:role].presence || "editor")
    if membership.save
      render_section(topic, toast: "#{actor.name} ist jetzt Mitglied.")
    else
      render_section(topic, toast: membership.errors.full_messages.to_sentence)
    end
  end

  def update
    membership = TopicMembership.find(params[:id])
    membership.update!(role: params[:role])
    render_section(membership.topic)
  end

  def destroy
    membership = TopicMembership.find(params[:id])
    membership.destroy!
    render_section(membership.topic, toast: "#{membership.actor.name} entfernt.")
  end

  # PATCH /topics/:topic_id/visibility — members_only | internal_public.
  def set_visibility
    topic = find_topic
    topic.update!(visibility: params[:visibility])
    render_section(topic)
  end

  private

  def require_topic_stewardship
    # #602 S3: gleiche Regel wie fürs Thema selbst (Topic#manageable_by?) —
    # Admin, Ersteller oder owner-Mitglied; Gäste nie.
    topic = params[:topic_id] ? find_topic : TopicMembership.find(params[:id]).topic
    return if topic.manageable_by?(current_actor)
    raise AccessGate::Unauthorized, "Nur Admins oder Verantwortliche verwalten Mitglieder."
  end

  def find_topic
    Topic.visible_to(current_actor).find_by!(slug: params[:topic_id])
  end

  def render_section(topic, toast: nil)
    streams = [ turbo_stream.replace("topic_memberships_#{topic.id}",
      partial: "topics/memberships", locals: { topic: topic }) ]
    streams << helpers.toast_stream(message: toast) if toast
    render turbo_stream: streams
  end

  def controller_resource_type = "Topic"
  def controller_action_to_capability = "update"
end
