class InboxItemsController < ApplicationController
  before_action :set_item, only: [:show, :card, :update, :destroy, :process_now, :archive, :poll]

  include KnowledgeStackHelpers
  include StackRedirects
  include InboxItemUploads   # #634: store_uploaded_file! (geteilt mit /share)

  # #618: /inbox ist eine Blade-Stack-Seite — Einstieg ist das Inbox-
  # Listen-Blade, Items öffnen als Detail-Blades (inboxitem:<id>).
  def index
    params[:stack] = "list:inbox_items" if params[:stack].blank?
    @initial_stack_items  = build_initial_stack
    @initial_stack_bodies = bodies_for_initial_stack(@initial_stack_items)
  end

  # #163 Phase 5a-2: Listen-Blade fuer Cross-Entity-Stack.
  def list_card
    render partial: "inbox_items/list_blade_card", layout: false
  end

  # #618: Einzelfenster abgelöst — Detail lebt als Blade im Stack.
  def show
    redirect_to inbox_items_path(stack: "list:inbox_items,inboxitem:#{@item.id}")
  end

  # #618: Detail-Blade (Fetch beim Klick; Restore läuft über den Loader).
  def card
    render partial: "inbox_items/blade_card", locals: { item: @item }, layout: false
  end

  def create
    item =
      if (file = params[:file]).respond_to?(:original_filename)
        store_uploaded_file!(file)
      else
        InboxItem.create!(create_params.merge(creator: current_actor))
      end
    # #171 Phase 4: Quick-Add-Form akzeptiert optional topic_ids (Slugs
    # oder IDs). Wird hier nach dem Item-Insert verlinkt.
    attach_topics_from_params!(item)
    # Sprechenden Titel async holen, falls keiner mitgegeben wurde
    # (URL-Quickadd setzt nur source_url). Solid-Queue-Worker macht den
    # Rest, ohne den Web-Request zu blockieren.
    if item.source_url.present? && item.payload["title"].to_s.strip.blank? && item.title.to_s.strip.blank?
      FetchInboxTitleJob.perform_later(item.id)
    end
    if turbo_frame_request? || request.xhr?
      head :created, location: inbox_item_url(item)
    elsif (stay = stay_in_stack_redirect_to("inboxitem:#{item.id}"))
      # #627 v2 (Hans): Import aus dem Topic-Blade — das frische Item als
      # Detail-Blade an den AKTUELLEN Stack anhängen statt zur Inbox-
      # Seite zu springen; dort kann es direkt verarbeitet werden.
      redirect_to stay, notice: "Inbox-Eintrag angelegt."
    else
      redirect_to inbox_items_path(stack: "list:inbox_items,inboxitem:#{item.id}"), notice: "Inbox-Eintrag angelegt."
    end
  end

  def update
    @item.update!(update_params)
    redirect_to inbox_items_path(stack: "list:inbox_items,inboxitem:#{@item.id}"), notice: "Gespeichert."
  end

  def destroy
    @item.destroy!
    redirect_to inbox_items_path, notice: "Gelöscht."
  end

  # POST /inbox/:id/process — schedules den Run als Solid-Queue-Job.
  # Item wird sofort auf "processing" gesetzt, damit die UI das anzeigen
  # kann. Der Job übernimmt dann die eigentliche Verarbeitung asynchron.
  def process_now
    kind  = params[:processor_kind].presence || @item.suggested_processor_kind
    klass = Inbox::Registry.find(kind)
    raise "Unknown processor: #{kind.inspect}" unless klass

    payload_updates = {}
    payload_updates["prompt_template_slug"] = params[:prompt_template_slug] if params[:prompt_template_slug].present?
    payload_updates["confirm_whisper"]      = true if ActiveModel::Type::Boolean.new.cast(params[:confirm_whisper])
    payload_updates["confirm_diarize"]      = true if ActiveModel::Type::Boolean.new.cast(params[:confirm_diarize])  # #776
    # #934: Dokument-Import-Review bestätigt — inkl. der angehakten Aufgaben.
    if ActiveModel::Type::Boolean.new.cast(params[:confirm_import])
      payload_updates["confirm_import"]        = true
      payload_updates["confirmed_task_titles"] = Array(params[:task_titles]).map(&:to_s)
    elsif kind == "document_import"
      # Re-Analyse: ein früher gesetztes Bestätigungs-Flag darf nicht kleben,
      # sonst würde der Re-Run ohne Review direkt anlegen.
      payload_updates["confirm_import"] = false
    end
    @item.update!(payload: @item.payload.merge(payload_updates)) if payload_updates.any?

    # Optimistic UI: Status sofort auf processing, damit der User Feedback
    # sieht. Der Job wird ProcessorBase.run aufrufen, das setzt es selbst
    # nochmal auf processing → processed/failed/awaiting_confirmation.
    @item.update!(status: "processing", processor_kind: kind, error_message: nil)
    ProcessInboxItemJob.perform_later(@item.id, kind, current_actor.id)

    redirect_to inbox_items_path(stack: "list:inbox_items,inboxitem:#{@item.id}")
  end

  def archive
    # #670: optional als Dublette markieren — die KI-uuid der Quelle
    # landet im payload (Provenienz fürs Detail + spätere Auswertung).
    if (dup = params[:duplicate_of].presence)
      @item.update!(status: "archived",
                    payload: @item.payload.merge("duplicate_of" => dup))
      redirect_to inbox_items_path(stack: "list:inbox_items,inboxitem:#{@item.id}"),
                  notice: "Als Dublette archiviert." and return
    end
    @item.update!(status: "archived")
    redirect_to inbox_items_path, notice: "Archiviert."
  end

  # GET /inbox/:id/poll — Frontend-Polling-Endpoint für die "Wird
  # verarbeitet …"-Sektion. Solange der Status processing ist: 204.
  # Sobald sich was geändert hat: Turbo-Stream-Antwort mit Detail-
  # Frame-Replace + Toast-Append.
  def poll
    if @item.status == "processing"
      head :no_content
      return
    end

    # Vars für das Detail-Partial (analog zur show-Action).
    @suggested        = @item.suggested_processor_kind
    @processors       = Inbox::Registry.all
    @prompt_templates = PromptTemplate.order(:name)
    respond_to { |format| format.turbo_stream }
  end

  # Manuell den Folder-Scanner triggern (z.B. nach Drop einer Datei).
  def scan
    items = Inbox::FolderScanner.run(actor: current_actor)
    redirect_to inbox_items_path, notice: "#{items.size} neue Einträge gescannt."
  end

  private

  def set_item
    @item = InboxItem.visible_to(current_actor).find(params[:id])
  end

  def create_params
    p = params.permit(:source_kind, :source_url, :raw_content, :external_path,
                      :title, payload: {})
    p[:source_kind] ||= guess_source_kind(p)
    p
  end

  # store_uploaded_file! lebt seit #634 in InboxItemUploads (geteilt
  # mit dem Share-Endpoint).

  def update_params
    params.require(:inbox_item).permit(:title, :raw_content, :source_url)
  end

  # #171 Phase 4: nimmt aus den Form-Params topic_ids[] (Slugs oder IDs)
  # und hängt die zugehörigen Topics an das frisch erstellte InboxItem.
  # Idempotent, ignoriert unbekannte IDs/Slugs.
  def attach_topics_from_params!(item)
    raw = Array(params[:topic_ids]).map { |s| s.to_s.strip }.reject(&:blank?)
    return if raw.empty?
    raw.each do |id|
      topic = Topic.find_by(slug: id) || Topic.find_by(id: id.to_i)
      next unless topic
      InboxItemTopic.find_or_create_by!(inbox_item: item, topic: topic)
    end
  end

  # Wenn nicht explizit angegeben, raten wir aus URL/Content.
  def guess_source_kind(p)
    if p[:source_url].present?
      Inbox::Processors::YoutubeTranscribe.youtube_url?(p[:source_url]) ? "youtube_url" : "web_url"
    elsif p[:raw_content].present?
      "markdown"
    else
      "text"
    end
  end

  def controller_resource_type
    "InboxItem"
  end

  def controller_action_to_capability
    case action_name
    when "process_now", "archive", "scan" then "update"
    when "poll"                            then "read"
    else super
    end
  end
end
