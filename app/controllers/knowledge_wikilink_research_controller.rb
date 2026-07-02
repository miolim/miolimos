# #378 Phase 4 (Hans, 2026-05-26): Researcher-Triggers aus
# KnowledgeItemsController ausgelagert. Endpoints bleiben stabil ueber
# Route :to-Mapping:
#   POST /knowledge_items/:uuid/request_entity_import
#   POST /knowledge_items/:uuid/start_wikilink_research
#
# Beide Actions legen einen Task fuer `miolim_researcher@miolim.de` an;
# `start_wikilink_research` zusaetzlich einen WikilinkResearchJob fuer
# das Rendering-Indikator-Modell.
class KnowledgeWikilinkResearchController < ApplicationController
  # #806: Recherche-Agent konfigurierbar — Selbst-Hoster benennen ihren
  # eigenen Agenten via ENV; Default ist der historische Instanz-Agent.
  RESEARCHER_EMAIL = ENV.fetch("MIOLIMOS_RESEARCHER_EMAIL", "miolim_researcher@miolim.de").freeze

  before_action :set_item

  # JS-getriggerte Endpoints (Stimulus-Fetch); Auth ueber Session.
  skip_before_action :verify_authenticity_token,
    only: [:request_entity_import, :start_wikilink_research]

  WIKILINK_WITH_URL_RE = /
    \[\[
    ([^\]|\#\^]+)                    # title
    (?:\#[^\]|]+)?                   # optional heading
    (?:\^[^\]|]+)?                   # optional block anchor
    \|\s*(https?:\/\/[^\]\s]+)\s*    # source URL in alias slot
    \]\]
  /x

  # POST /knowledge_items/:uuid/request_entity_import
  # Bulk: scannt den KI-Body nach `[[Title | URL]]` ohne Ziel-KI und
  # legt EINEN Researcher-Task mit allen Entitaeten an.
  def request_entity_import
    researcher = AgentActor.find_by(email: RESEARCHER_EMAIL)
    unless researcher
      render(json: { error: "Researcher-Agent (#{RESEARCHER_EMAIL}) nicht gefunden." },
             status: :unprocessable_entity)
      return
    end

    entities = scan_importable_entities(@item)
    if entities.empty?
      render(json: { count: 0, message: "Keine fehlenden Wikilinks mit Quell-URL gefunden." })
      return
    end

    body_lines = [
      "Forschungsergebnis: [[#{@item.title}]]",
      "",
      "Anlegen / nachrecherchieren der folgenden Entitäten — Item-Type pro Eintrag selbst beurteilen (Person / Organisation / Quelle / sonstige KI). Bei Bedarf Felder description / affiliation / Email aus der angegebenen URL erschließen.",
      "",
      *entities.map { |name, url| "- **#{name}** — Quelle: #{url}" },
      "",
      "Nach erfolgreichem Anlegen: Status-Comment mit Liste der angelegten Datensätze (KI-UUID bzw. Source-Slug), dann Task auf `done`."
    ]

    task = Task.create!(
      creator:  current_actor,
      assignee: researcher,
      title:    "Entitäten importieren aus: #{@item.title.truncate(80)}",
      description: body_lines.join("\n"),
      status:   :open,
      tags:     ["entity_import"]
    )

    entities.each do |name, url|
      WikilinkResearchJob.create!(
        source_knowledge_item_id: @item.uuid,
        target_title:             name,
        target_source_url:        url,
        task_id:                  task.id
      )
    rescue ActiveRecord::RecordNotUnique
      next
    end

    render json: { count: entities.size, task_id: task.id, task_url: task_path(task) }
  end

  # POST /knowledge_items/:uuid/start_wikilink_research
  # Per-Wikilink: legt einen einzigen Researcher-Task + Job fuer EIN
  # `[[Title|URL]]` an. Idempotent: bestehender Job wird zurueckgegeben.
  def start_wikilink_research
    researcher = AgentActor.find_by(email: RESEARCHER_EMAIL)
    unless researcher
      render(json: { error: "Researcher-Agent (#{RESEARCHER_EMAIL}) nicht gefunden." },
             status: :unprocessable_entity)
      return
    end

    title = params[:title].to_s.strip
    url   = params[:source_url].to_s.strip
    if title.empty? || url.empty?
      render(json: { error: "title und source_url erforderlich" },
             status: :unprocessable_entity)
      return
    end

    existing = WikilinkResearchJob.find_by(
      source_knowledge_item_id: @item.uuid, target_title: title
    )
    if existing
      render(json: { task_id: existing.task_id, task_url: task_path(existing.task_id),
                     state: "already_running" })
      return
    end

    # #672 (Hans): Auftrags-Prosa aus der editierbaren Vorlage
    # (Einstellungen → Wissens-Import). Platzhalter füllen; die
    # mechanischen Schluss-Zeilen (PATCH/Job-ID/done) hängt der Server an.
    prose = helpers.wikilink_research_prompt
                   .gsub("{{title}}",  title)
                   .gsub("{{url}}",    url)
                   .gsub("{{source}}", @item.title.to_s)
    body = [
      prose.strip,
      "",
      "Nach Anlage: PATCH `/api/v1/wikilink_research_jobs/<dieser-job-id>` mit `{\"target_knowledge_item_id\": \"<uuid>\"}`, damit das Rendering den Status auf 'fertig' setzen kann. Job-ID liegt im Task-Body unten.",
      "",
      "Dann diesen Task auf `done` setzen."
    ]

    job = nil
    Task.transaction do
      task = Task.create!(
        creator:  current_actor,
        assignee: researcher,
        title:    "Recherche: #{title.truncate(80)}",
        description: body.join("\n"),
        status:   :open,
        tags:     ["wikilink_research"]
      )
      job = WikilinkResearchJob.create!(
        source_knowledge_item_id: @item.uuid,
        target_title:             title,
        target_source_url:        url,
        task_id:                  task.id
      )
      task.update!(description: body.join("\n") + "\n\nJob-ID: #{job.id}")
    end

    render json: { task_id: job.task_id, task_url: task_path(job.task_id),
                   job_id: job.id, state: "started" }
  end

  private

  def set_item
    @item = KnowledgeItem.find(params[:knowledge_item_uuid] || params[:uuid])
  end

  # Liefert eindeutige [Name, URL]-Paare fuer [[Name|https://...]]-
  # Wikilinks im KI-Content, deren Title noch nicht als KI auflöst.
  def scan_importable_entities(item)
    content = FileProxy.read_body(actor: current_actor, knowledge_item: item).to_s
    seen = {}
    content.scan(WIKILINK_WITH_URL_RE) do |title_raw, url_raw|
      title = title_raw.to_s.strip
      url   = url_raw.to_s.strip
      next if title.empty? || url.empty?
      next if KnowledgeItem.by_title_ci(title).exists?
      seen[title.downcase] ||= [title, url]
    end
    seen.values
  end

  def controller_resource_type        = "KnowledgeItem"
  def controller_action_to_capability = "update"
end
