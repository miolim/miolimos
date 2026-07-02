class SourcesController < ApplicationController
  before_action :set_source, only: [:show, :edit, :update, :destroy, :card]

  include KnowledgeStackHelpers

  # #631 v3 (Hans): /sources ist eine Blade-Stack-Seite — Einstieg ist
  # das Quellen-Listen-Blade, Klick öffnet die Quelle als Blade
  # (kind src). Die alte Split-Pane-Vollseite ist abgelöst.
  def index
    params[:stack] = "list:sources" if params[:stack].blank?
    @initial_stack_items  = build_initial_stack
    @initial_stack_bodies = bodies_for_initial_stack(@initial_stack_items)
  end

  def show
    @cited_kis = @source.knowledge_items.order(:title)
    # Vollbild-Aufruf (Bookmark, Browser-Reload) → Stack mit Liste +
    # Quelle als Blade. Frame-Request → Detail-Partial (show.html.erb).
    if !turbo_frame_request? && request.format.html?
      redirect_to sources_path(stack: "list:sources,src:#{@source.slug}") and return
    end
  end

  # Card-Fragment für den blade-stack-Controller (analog zu
  # KnowledgeItemsController#card).
  def card
    render partial: "sources/stack_card", locals: { source: @source }
  end

  # #163 Phase 5a-2: Listen-Blade fuer Cross-Entity-Stack.
  def list_card
    render partial: "sources/list_blade_card", layout: false
  end

  def new
    @source = Source.new(csl_type: "book")
  end

  def create
    @source = Source.new(source_params.merge(creator: current_actor))
    if @source.save
      sync_identifiers(@source, params[:identifiers])
      sync_creators(@source, params[:creators])
      redirect_to sources_path(stack: "list:sources,src:#{@source.slug}"), notice: "Quelle angelegt."   # direkt (Flash, #613)
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    Source.transaction do
      # #649: Die Autoren-Sub-Section submittet NUR creators[] (kein
      # source-Param) — require(:source) warf dann 400 und der Frame
      # zeigte „Content missing". Felder-Update nur, wenn vorhanden.
      @source.update!(source_params) if params[:source].present?
      sync_identifiers(@source, params[:identifiers])
      sync_creators(@source, params[:creators])
    end
    if params[:in_stack].present?
      # Inline-Edit aus dem Stack: TurboFrame ersetzt sich selbst, kein
      # Page-Wechsel. Auto-submit on-blur löst pro Feld einen Submit aus.
      # #584: Beim Slug-Inline-Edit trägt das DOM noch die ALTE Frame-ID —
      # also die ersetzen, nicht die neue.
      frame_slug = @source.saved_change_to_slug? ? @source.saved_change_to_slug[0] : @source.slug
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.replace("source_detail_#{frame_slug}",
            partial: "sources/stack_card_detail", locals: { source: @source })
        end
        format.html do
          render partial: "sources/stack_card_detail", locals: { source: @source }
        end
      end
      return
    end
    if params[:in_pane].present?
      # #198 Phase 2: Inline-Edit im Split-Pane-Detail. Statischer
      # `source_detail`-Frame (nicht slug-suffixed wie im Stack).
      @cited_kis = @source.knowledge_items.order(:title)
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.replace("source_detail",
            partial: "sources/detail", locals: { source: @source, cited_kis: @cited_kis })
        end
        format.html do
          render partial: "sources/detail", locals: { source: @source, cited_kis: @cited_kis }
        end
      end
      return
    end
    redirect_to sources_path(stack: "list:sources,src:#{@source.slug}"), notice: "Gespeichert."   # direkt (Flash, #613)
  rescue ActiveRecord::RecordInvalid
    render :edit, status: :unprocessable_entity
  end

  def destroy
    @source.destroy!
    redirect_to sources_path, notice: "Quelle gelöscht."
  end

  # Autocomplete für [@-Cite-Syntax: liefert {slug, label, creators}.
  # Sucht über slug, title, container_title UND Author/Creator-Namen
  # (über source_creators → KI-Title) — damit man Quellen aus dem
  # Gedächtnis zitieren kann ohne den Slug-Key zu kennen.
  def suggest
    q = params[:q].to_s.strip.downcase
    scope = Source.includes(source_creators: :knowledge_item).order(:title).limit(10)
    if q.present?
      like = "%#{q}%"
      # Sub-Query: Source-IDs, deren Creator-KI-Titel matchen.
      creator_source_ids = SourceCreator
        .joins(:knowledge_item)
        .where("lower(knowledge_items.title) LIKE :q OR " \
               "lower(coalesce(knowledge_items.first_name,'')) LIKE :q OR " \
               "lower(coalesce(knowledge_items.last_name,'')) LIKE :q",
               q: like)
        .pluck(:source_id).uniq
      scope = scope.where(
        "lower(slug) LIKE :q OR lower(title) LIKE :q OR " \
        "lower(coalesce(container_title,'')) LIKE :q OR " \
        "id IN (:cs)",
        q: like, cs: creator_source_ids
      )
    end
    items = scope.map do |s|
      year = s.issued_date&.year || s.issued_string.to_s.scan(/\d{4}/).first
      creators = s.display_authors.presence
      label_parts = [s.title]
      label_parts << "(#{year})" if year
      { "slug"     => s.slug,
        "title"    => s.title,
        "label"    => label_parts.join(" "),
        "creators" => creators,
        "csl_type" => s.csl_type }
    end
    render json: { items: items }
  end

  private

  # Gruppiert die Sources-Liste nach einem Schlüssel; nil/"" → keine
  # Gruppierung (Single-Bucket "" mit allen Sources). Stabile Reihenfolge
  # der Buckets via Sort innerhalb des Hashes.
  def group_sources(sources, key)
    return { nil => sources.to_a } if key.blank?
    case key
    when "csl_type"
      sources.group_by(&:csl_type).sort_by { |k, _| k.to_s }.to_h
    when "year"
      sources.group_by { |s| s.issued_date&.year || s.issued_string.to_s.scan(/\d{4}/).first }
              .sort_by { |k, _| k.to_i }.reverse.to_h
    when "container"
      sources.group_by { |s| s.container_title.presence || "(ohne Container)" }
              .sort_by { |k, _| k.to_s.downcase }.to_h
    else
      { nil => sources.to_a }
    end
  end

  def set_source
    @source = Source.find_by!(slug: params[:slug])
  end

  def source_params
    params.require(:source).permit(
      :slug, :csl_type, :title, :container_title, :publisher, :publisher_place,
      :issued_string, :accessed, :edition, :volume, :issue, :pages,
      :abstract, :language, :archive, :archive_location, :url,
      :parent_source_id, :jurisdiction, :court, :docket_number
    ).tap do |p|
      # issued_date aus issued_string parsen, wenn möglich.
      if (s = p[:issued_string]).present?
        if (d = parse_loose_date(s))
          p[:issued_date] = d
        end
      end
    end
  end

  def parse_loose_date(s)
    return Date.new(s.to_i, 1, 1) if s =~ /\A\d{4}\z/
    Date.parse(s) rescue nil
  end

  def sync_identifiers(source, ids_param)
    return if ids_param.nil?
    rows = Array(ids_param).filter_map do |row|
      row = row.permit(:scheme, :value).to_h if row.respond_to?(:permit)
      row = row.transform_keys(&:to_s)
      next nil if row["value"].to_s.strip.empty?
      { "scheme" => row["scheme"].to_s, "value" => row["value"].to_s.strip }
    end
    source.source_identifiers.destroy_all
    rows.each { |r| source.source_identifiers.create!(scheme: r["scheme"], value: r["value"]) }
  end

  UUID_RE = /\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/

  def sync_creators(source, creators_param)
    return if creators_param.nil?
    rows = Array(creators_param).filter_map.with_index do |row, i|
      row = row.permit(:knowledge_item_uuid, :role).to_h if row.respond_to?(:permit)
      row = row.transform_keys(&:to_s)
      value = row["knowledge_item_uuid"].to_s.strip
      next nil if value.empty?
      # #584-Folge (Hans): das Eingabefeld zeigt TITEL, keine UUIDs mehr.
      # Nicht-UUID-Werte werden als Name aufgelöst — bestehende Person/Org
      # (Titel/Alias, CI) oder neuer Namens-Stub (wie beim API-Import).
      uuid = if value.match?(UUID_RE)
               value
             else
               Authorship.find_or_create_person(value, current_actor).uuid
             end
      { uuid: uuid, role: row["role"].to_s.presence || "author", position: i }
    end
    source.source_creators.destroy_all
    rows.each do |r|
      source.source_creators.create!(knowledge_item_uuid: r[:uuid], role: r[:role], position: r[:position])
    end
  end

  def controller_resource_type
    "Source"
  end
end
