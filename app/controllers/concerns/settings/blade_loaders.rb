# #613: Daten-Loader der Einstellungs-Blades — 1:1 aus den alten
# index/show-Actions der Einzel-Controller. Gemeinsam genutzt von
# Settings::BladesController (Card-Fetch beim Klick) und
# SettingsController (Stack-Restore: /settings?stack=...,settings:<page>
# rendert die Cards serverseitig und braucht dieselben @-Vars).
module Settings::BladeLoaders
  extend ActiveSupport::Concern

  private

  def load_accounts
    @credentials = OauthCredential.includes(:actor).order(:email_address)
  end

  def load_users
    @users = HumanActor.order(:name)
  end

  def load_agents
    @agents = AgentActor.order(:name)
  end

  def load_teams
    @teams = Team.includes(team_memberships: :actor).order(:name)
  end

  def load_templates
    @topic_templates = Topic.templates.order(:name)
  end

  def load_task_templates
    @task_templates    = TaskTemplate.order(:title)
    @new_task_template = TaskTemplate.new
    @agent_actors      = AgentActor.order(:name)
  end

  def load_ki_templates
    @ki_templates    = KiTemplate.order(:name)
    @new_ki_template = KiTemplate.new
  end

  def load_prompt_templates
    @prompt_templates = PromptTemplate.order(:name)
  end

  # #1036: Dokument- & E-Mail-Vorlagen = Notiz-KIs mit Tag "vorlage:<typ>",
  # gruppiert nach Typ (Reihenfolge = KINDS im Controller).
  def load_document_templates
    @document_templates = Settings::DocumentTemplatesController::KINDS.index_with do |kind|
      KnowledgeItem.templates_for(kind).to_a
    end
  end

  def load_llm_activities
    # #613/#614: Filter leben jetzt IM Blade (Turbo-Frame auf den
    # Card-Endpoint) — Status/Kind kommen als Query-Params mit.
    @status_filter = params[:status].presence
    @kind_filter   = params[:kind].presence
    @activities = LlmActivity
                    .by_status(@status_filter)
                    .by_kind(@kind_filter)
                    .recent
                    .limit(200)
    @counts_by_status = LlmActivity.group(:status).count
  end

  def load_knowledge_import
    @inbox_path = WikiImporter::INBOX_PATH.to_s
    @prompt     = helpers.chat_import_prompt
    @prompt_is_default = (@prompt == ApplicationHelper::CHAT_IMPORT_PROMPT_DEFAULT)
    # #672: editierbare Wikilink-Recherche-Vorlage.
    @research_prompt = helpers.wikilink_research_prompt
    @research_prompt_is_default = (@research_prompt == ApplicationHelper::WIKILINK_RESEARCH_PROMPT_DEFAULT)
  end

  def load_relations
    @relation_types = RelationType.order(:name)
    @new_type       = RelationType.new
    rows = Relation.active
                   .where.not(label: [nil, ""])
                   .group(:label)
                   .order(Arel.sql("COUNT(*) DESC"))
                   .pluck(:label, Arel.sql("COUNT(*)"),
                          Arel.sql("COUNT(DISTINCT source_uuid)"))
    @label_stats = rows.map do |label, count, sources|
      example = Relation.active.where(label: label).order(recognized_at: :desc, created_at: :desc).first
      example_source = example && KnowledgeItem.find_by(uuid: example.source_uuid)
      {
        label:          label,
        count:          count,
        source_count:   sources,
        example_source: example_source,
        example_anchor: example&.anchor_id,
        has_type:       RelationType.find_by_label(label).present?
      }
    end
    @unlabeled = Relation.active.where(label: [nil, ""]).count
    @orphaned  = Relation.orphaned.count
  end

  def load_tag_icons
    @mapping = helpers.tag_icons_map
  end

  # #1051: Sicherheit — 2FA-Zustand des ECHTEN eingeloggten Nutzers
  # (real_actor, nie der Preview-Actor) + ggf. laufendes Enrollment
  # (Kandidaten-Secret aus der Session).
  def load_security
    @otp_actor        = real_actor
    @otp_setup_secret = session[:otp_setup_secret]
  end

  # preferences/signature: keine Loader (Views lesen current_actor/Helpers).
end
