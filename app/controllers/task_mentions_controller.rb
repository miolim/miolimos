# Web-UI nested controller: /tasks/:task_id/mentions
# Erwähnen von KIs an einer Task. Standard-Verhalten = Kontakte
# (Person/Org-KI), via Param `kind=knowledge` werden statt dessen
# allgemeine Wissens-KIs (Notes etc.) gehandhabt — eigene Sektion
# „Verknüpftes Wissen" im Task-Detail.
class TaskMentionsController < ApplicationController
  def create
    task = find_visible!(Task, params[:task_id])   # #1675
    ki   = resolve_mention_from_params

    TaskMention.find_or_create_by!(task: task, mentioned_uuid: ki.uuid) if ki

    respond_with_chips(task)
  end

  def destroy
    task = find_visible!(Task, params[:task_id])   # #1675
    ki   = KnowledgeItem.find_by(uuid: params[:id]) ||
           PersonKiResolver.find(params[:id])
    TaskMention.find_by(task: task, mentioned_uuid: ki&.uuid)&.destroy
    @unlinked_ki = ki

    respond_with_chips(task)
  end

  private

  def kind
    params[:kind].to_s == "knowledge" ? :knowledge : :contact
  end

  def resolve_mention_from_params
    if (text = params[:create_with].to_s.strip).present?
      quick_create(text)
    else
      raw = params.require(:mentioned_uuid)
      # #1675: auch das ZIEL muss der Nutzer sehen dürfen.
      only_visible(KnowledgeItem.find_by(uuid: raw) || PersonKiResolver.find(raw))
    end
  end

  # Quick-Create unterscheidet sich nach kind: Kontakt = Person mit
  # First/Last-Name-Heuristik aus dem Eingabetext, Wissen = einfache Note.
  def quick_create(text)
    if kind == :knowledge
      FileProxy.create(
        actor:     Current.actor,
        title:     text,
        item_type: :note,
        content:   ""
      )
    else
      # #1677 (aus immoOS #1661): eine Stelle für alle — PersonKiResolver.aus_text!
      PersonKiResolver.aus_text!(text, item_type: params[:create_type].presence || :person,
                                       actor: Current.actor)
    end
  end

  def respond_with_chips(task)
    task.reload
    chips_id = kind == :knowledge ? "task_knowledge_chips_#{task.id}" : "task_contacts_chips_#{task.id}"
    chips_partial = kind == :knowledge ? "tasks/knowledge_chips" : "tasks/contacts_chips"
    streams = [
      turbo_stream.replace(chips_id,
        partial: chips_partial, locals: { task: task })
    ]
    if action_name == "destroy" && @unlinked_ki
      streams << helpers.toast_stream(
        message:  "Erwähnung '#{@unlinked_ki.display_name}' entfernt",
        undo_url: task_mentions_path(task, kind: kind),
        undo_payload: { mentioned_uuid: @unlinked_ki.uuid, kind: kind.to_s }
      )
    end
    respond_to do |format|
      format.turbo_stream { render turbo_stream: streams }
      format.json { render json: { ok: true } }
      format.html { redirect_back fallback_location: task_path(task) }
    end
  end

  def controller_resource_type
    "Task"
  end

  def controller_action_to_capability
    "update"
  end
end
