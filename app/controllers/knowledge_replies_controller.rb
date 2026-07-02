# #384 Phase 3a (Hans, 2026-05-27): Reply-KI-Endpoint fuer
# Dialog-Beitraege an einer KI. Phase 3b ergaenzt analog Tasks als
# Parent. Reply-KIs sind eigenstaendige KIs mit item_type=:reply,
# parent_type=„KnowledgeItem\", parent_uuid=<parent.uuid>.
class KnowledgeRepliesController < ApplicationController
  before_action :set_parent_ki

  skip_before_action :verify_authenticity_token, only: [:create, :update, :destroy]

  # GET /knowledge_items/:knowledge_item_uuid/replies
  # #232 (Hans, 2026-06-01): Liefert NUR das Replies-Listen-Frame-Fragment
  # fuer gezielte Live-Reloads (turbo-frame src), viewer-korrekt gerendert.
  def index
    render partial: "knowledge_items/replies_list", locals: { item: @parent_ki }
  end

  # POST /knowledge_items/:knowledge_item_uuid/replies
  # Body-Param: body (Markdown), optional draft (true|false).
  def create
    body  = params[:body].to_s
    draft = ActiveModel::Type::Boolean.new.cast(params[:draft])
    # FileProxy.create verlangt einen `title` (slugifiziert die Datei).
    # Wir uebergeben einen Platzhalter und nullen den Title nach dem
    # Anlegen — Reply-KIs zeigen `@author · zeit` als Identifikator
    # (display_label).
    placeholder = "Reply #{Time.current.strftime('%Y%m%d-%H%M%S')}"
    reply = FileProxy.create(
      actor:     current_actor,
      title:     placeholder,
      item_type: :reply,
      content:   body
    )
    reply.update!(
      title:        nil,
      parent_type:  "KnowledgeItem",
      parent_uuid:  @parent_ki.uuid,
      published_at: draft ? nil : Time.current
    )
    # Topic-Vererbung: Reply uebernimmt die Topics des Parents,
    # damit es im Diskussions-Tab desselben Topics auftaucht.
    @parent_ki.topics.each do |topic|
      reply.knowledge_item_topics.find_or_create_by!(topic: topic)
    end
    # #518 (Hans, 2026-06-05): in der KI-Diskussion @-erwähnte Agenten
    # anstupsen (nur veröffentlichte Beiträge), analog zur Aufgaben-Antwort.
    unless draft
      BuilderInboxPoke.poke_mentioned_agents(
        reply, except: current_actor,
        note: "Antwort an Dich in KI „#{@parent_ki.title}“"
      )
    end
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace(
          "knowledge_replies_#{@parent_ki.uuid}",
          partial: "knowledge_items/replies_section",
          # #451 (Hans, 2026-06-01): nach Entwurf-Save den Compose
          # refokussieren (siehe task_replies_controller).
          locals:  { item: @parent_ki, focus_compose: draft }
        )
      end
      format.html { redirect_to knowledge_item_path(@parent_ki.uuid) }
    end
  end

  # PATCH /knowledge_items/:knowledge_item_uuid/replies/:id
  # Body-Param: body (optional), publish (optional, "1" → set
  # published_at=now). Nur eigene Reply, nur solange editable_by?.
  def update
    reply = KnowledgeItem.replies.find_by(uuid: params[:id])
    raise ActiveRecord::RecordNotFound unless reply
    unless reply.editable_by?(current_actor)
      head :forbidden and return
    end
    new_body = params[:body]
    if new_body.present?
      FileProxy.update(actor: current_actor, knowledge_item: reply, content: new_body)
    end
    if ActiveModel::Type::Boolean.new.cast(params[:publish]) && reply.published_at.nil?
      reply.update!(published_at: Time.current)
    end
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace(
          "knowledge_replies_#{@parent_ki.uuid}",
          partial: "knowledge_items/replies_section",
          locals:  { item: @parent_ki }
        )
      end
      format.html { redirect_to knowledge_item_path(@parent_ki.uuid) }
    end
  end

  # DELETE /knowledge_items/:knowledge_item_uuid/replies/:id
  # #384 Phase 3d (Hans, 2026-05-27): Eigene letzte Reply loeschen.
  # editable_by? prueft „nur eigene, nur solange keine fremde Folge-
  # Reply existiert" — identische Regel wie fuer Edit.
  def destroy
    reply = KnowledgeItem.replies.find_by(uuid: params[:id])
    raise ActiveRecord::RecordNotFound unless reply
    # #536: Löschen eigener Beiträge immer erlaubt (deletable_by?), auch
    # nach fremder Folge-Antwort — anders als Bearbeiten.
    unless reply.deletable_by?(current_actor)
      head :forbidden and return
    end
    reply.destroy!
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace(
          "knowledge_replies_#{@parent_ki.uuid}",
          partial: "knowledge_items/replies_section",
          locals:  { item: @parent_ki }
        )
      end
      format.html { redirect_to knowledge_item_path(@parent_ki.uuid) }
    end
  end

  private

  def set_parent_ki
    @parent_ki = KnowledgeItem.find(params[:knowledge_item_uuid])
  end

  def controller_resource_type        = "KnowledgeItem"
  # #232: index ist reiner Lese-Zugriff (Listen-Fragment), Rest braucht update.
  def controller_action_to_capability = action_name == "index" ? "read" : "update"
end
