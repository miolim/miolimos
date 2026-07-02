# Block-Anchor-Operationen an KIs (Comment-at-Block, Research-at-Block,
# Backlinks-zu-Block). Aus KnowledgeItemsController (#127) ausgelagert.
# URLs bleiben stabil:
#
#   POST /knowledge_items/:uuid/ensure_anchor      → create
#   POST /knowledge_items/:uuid/comment_at         → comment
#   POST /knowledge_items/:uuid/start_research_at  → research
#   GET  /knowledge_items/:uuid/backlinks          → backlinks
#
# Frontend-Aufrufer ist primär `paragraph_actions_controller.js`. Da
# alle Endpoints aus Stimulus-fetch kommen, CSRF skippen.
class KnowledgeAnchorsController < ApplicationController
  before_action :set_item
  skip_before_action :verify_authenticity_token

  # Idempotent: stellt sicher, dass ein Block einen stabilen `^id`
  # hat. Eingang: block_index (z.B. "block-3") oder anchor (existing).
  # Wenn block-N angefragt wird und der Block im Source noch keinen
  # `^id` hat: kurzen Hash erzeugen, ans Source-Markdown anhängen,
  # speichern, ID zurückgeben.
  def create
    anchor = body_ops.resolve_anchor!(params.require(:anchor).to_s)
    render json: { uuid: @item.uuid, anchor: anchor }
  rescue ArgumentError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # Erzeugt ein Comment-KI an einem Anker. Wenn der Anker noch nicht
  # stabil ist (block-N), wird er erst gesetzt. Antwort: UUID des
  # neuen KI, sodass der blade-stack-Controller die Card anhängen und
  # in den Edit-Mode öffnen kann.
  def comment
    comment, anchor = body_ops.comment_at(params.require(:anchor).to_s)
    render json: { uuid: comment.uuid, anchor: anchor }
  rescue ArgumentError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # #467 (Hans, 2026-06-02): Erzeugt eine Aufgabe an einem Anker. Die
  # Beschreibung traegt einen Wikilink auf den Anker ([[Title^anchor]]),
  # der Titel die markierte Stelle (vom Frontend uebergeben) oder einen
  # Default. block-N-Anker werden vorher stabilisiert. Antwort: task_id,
  # damit der blade-stack-Controller die Task-Card anhaengen kann.
  def task
    anchor = body_ops.resolve_anchor!(params.require(:anchor).to_s)
    if @item.reply?
      # #466 (Hans, 2026-06-02): Aufgabe aus einer Antwort. Titel NICHT
      # mit dem markierten Text vorbelegen („Titel leer lassen") — Task
      # verlangt aber presence, daher neutraler Platzhalter, den das
      # Frontend selektiert, sodass Hans ihn direkt ueberschreibt.
      # Wikilink mit Alternate-Display „Thread-Antwort"; der Anker-only-
      # Link loest ueber den Resolver auf den Parent (Aufgabe/KI) auf.
      link  = "[[^#{anchor}|Thread-Antwort]]"
      title = "Neue Aufgabe"
    else
      link  = @item.anchor_wikilink(anchor)   # #664: trägt auch bei Titeln mit |
      title = params[:title].to_s.strip.presence || "Aufgabe zu: #{@item.title}"
    end

    # #512 (Hans, 2026-06-04): Lupe legt eine Recherche-AUFGABE an, die aufs
    # Entitäts-Recherche-Verfahren verweist (statt eines asynchronen LLM-Jobs).
    if ActiveModel::Type::Boolean.new.cast(params[:research])
      snippet     = params[:title].to_s.strip.presence
      title       = "Recherche: #{snippet || @item.title}"
      hints       = params[:hints].to_s.strip
      description = +"Recherche-Auftrag zum Absatz #{link}.\n\n"
      description << "Verfahren: [[Verfahren: Entitäts-Recherche]] — Identität und Quellen prüfen und einen belegten Steckbrief anlegen. " \
                     "(Geht es nicht um eine Entität, sondern einen Sachverhalt: [[Verfahren: Recherche]].)"
      description << "\n\nHinweise: #{hints}" if hints.present?
    else
      description = link
    end

    task = Task.create!(title: title.truncate(120),
                        description: description,
                        creator: current_actor)
    render json: { task_id: task.id, reply: @item.reply? && description == link }
  rescue ArgumentError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # Schedule eine LLM-Recherche zu einem Absatz-Anker. Der Job läuft
  # asynchron in der Solid Queue, ruft Llm::ChatClient mit dem
  # PromptTemplate `paragraph_research` (in Settings editierbar), und
  # legt eine Notiz an, deren Body mit der ausgeschriebenen Anker-
  # Referenz beginnt — wie ein manueller Comment.
  def research
    anchor = body_ops.resolve_anchor!(params.require(:anchor).to_s)
    hints  = params[:hints].to_s.strip
    ParagraphResearchJob.perform_later(@item.uuid, anchor, hints, current_actor.id)
    render json: { ok: true }
  rescue ArgumentError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # Backlinks für einen Anker — alle KIs, die per [[Title^anchor]] auf
  # diesen Block verweisen.
  def backlinks
    anchor = params.require(:anchor).to_s
    refs   = KnowledgeItemReference.where(target_uuid: @item.uuid,
                                          anchor_type: :block,
                                          anchor_text: anchor)
                                   .includes(:source)
    items = refs.filter_map(&:source).uniq
    render json: {
      anchor: anchor,
      items:  items.map { |k| helpers.backlink_source_descriptor(k) }
    }
  end

  private

  def set_item
    @item = KnowledgeItem.find(params[:uuid])
  end

  def body_ops
    @body_ops ||= KnowledgeItemBodyOps.new(@item, actor: current_actor)
  end

  def controller_resource_type
    "KnowledgeItem"
  end

  def controller_action_to_capability
    case action_name
    when "backlinks" then "read"
    when "create"    then "update"
    when "comment", "research", "task" then "create"
    else super
    end
  end
end
