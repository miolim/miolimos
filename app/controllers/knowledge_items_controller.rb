class KnowledgeItemsController < ApplicationController
  include SlugListParams
  include KnowledgeStackHelpers

  before_action :set_item,     only: [:show, :edit, :update, :destroy,
                                      :file, :quote_from_clipboard,
                                      :supersede, :unsupersede, :identifiers, :addresses, :bank_accounts, :vat_exempt,
                                      :complete_from_url,
                                      :toggle_personally_known, :toggle_render_mode]
  before_action :set_any_item, only: [:restore]

  # JS-getriggerte Endpoints, die kein Form rendern können (Stimulus-
  # Controller-fetch). CSRF skippen ist hier OK — Auth läuft über die
  # Session, und die Aktionen sind low-stakes (UUID-Lookup, Wikilink-
  # Quick-Create, Clipboard-Quote).
  skip_before_action :verify_authenticity_token,
    only: [:resolve, :wikilink_create, :quote_from_clipboard,
           :supersede, :unsupersede]

  def index
    scope = KnowledgeItem.visible_to(current_actor).non_reply   # #436: Reply-KIs nicht in der Wissens-Liste
    # #460 (Hans, 2026-06-04): Abgelöste KIs standardmäßig ausblenden;
    # Toggle ?superseded=1 zeigt sie wieder (analog done/deleted-Filter).
    @show_superseded = params[:superseded].to_s == "1"
    scope = scope.not_superseded unless @show_superseded
    scope = scope.where(item_type: params[:item_type]) if params[:item_type].present?
    if params[:topic_slug].present?
      scope = scope.joins(:topics).where(topics: { slug: params[:topic_slug] })
    end
    if (q = params[:q].to_s.strip).length >= 2
      like = "%#{q.downcase}%"
      scope = scope.where("LOWER(title) LIKE :q", q: like)
    end

    # #87: Standardisierte Sort-Parameter.
    @sort = (params[:sort].presence || "title").to_s
    @dir  = (params[:dir].presence  || "asc").to_s
    direction = @dir == "desc" ? :desc : :asc
    # #221: Creator preloaden — _list_row.html.erb rendert creator.name
    # in der erweiterten Spalten-Ansicht.
    # #486 (Hans, 2026-06-03): Verweis-Assoziationen preloaden, damit die
    # Verweis-Zähler in der Listen-Row kein n+1 erzeugen.
    scope = scope.includes(:creator, :outgoing_references, :incoming_references)
    @items = case @sort
             when "file_updated_at" then scope.order(file_updated_at: direction)
             when "file_created_at" then scope.order(file_created_at: direction)
             when "item_type"       then scope.order(item_type: direction).order(:title)
             else                        scope.order(Arel.sql("LOWER(title) #{direction}"))
             end

    # #163 Phase 6c: /knowledge_items ist eine Blade-Stack-Seite.
    # Default-Stack `list:knowledge_items` rendert die Wissens-Liste
    # als erste Card; Klicks appenden KI-Detail-Cards. Legacy-Param
    # `?selected=<uuid>` wird auf das Stack-Format gemappt.
    if params[:stack].blank?
      tokens = ["list:knowledge_items"]
      tokens << params[:selected] if params[:selected].present?
      params[:stack] = tokens.join(",")
    end
    @initial_stack_items  = build_initial_stack
    @initial_stack_bodies = bodies_for_initial_stack(@initial_stack_items)

    # Cross-Navigation: ?new_type=direct_quote&bib_source=foo öffnet
    # direkt eine New-Card im initial-Stack (z.B. wenn der User von der
    # Source-Detail-Seite "+ Quote" geklickt hat).
    @new_card_type       = params[:new_type].to_s.presence
    @new_card_bib_source = params[:bib_source].to_s.presence
  end

  # #191 pinned/toggle_pin + #196 detail_pane + card sind in
  # KnowledgeStackController ausgelagert (#203 Phase E.1).

  # #257: Listen-Blade fuer das Sidebar-Plus an „Wissen". Das Partial
  # `index_list_blade` laedt @items/@sort/@dir selbst, wenn sie nicht
  # gesetzt sind — die Action rendert es nur layoutlos als Fragment.
  def list_card
    render partial: "knowledge_items/index_list_blade", layout: false
  end

  # #257 follow-up: Listen-Blade fuer das Sidebar-Plus an „Personen".
  # Personen + Organisationen; self-contained Partial.
  def persons_list_card
    render partial: "knowledge_items/persons_list_blade", layout: false
  end

  def show
    @body_html = load_body_html(@item)
  end

  def new
    @draft = KnowledgeItem.new
    # Vorauswahl der Themen, wenn aus einem Topic-Tab gekommen.
    @default_topic_slugs = params[:topic_slug].to_s
    # Picker reicht den gewählten Type via ?type=… durch — bestimmt
    # das vorausgewählte Item im Form (und später das typspezifische Partial).
    @default_type = params[:type].to_s.presence
    render_stack_new_card if params[:in_stack].present?
  end

  def create
    bib_source = resolve_or_create_bib_source!
    # #739 (Hans): Quick-Create ohne Titel soll NICHT an der Titel-Pflicht
    # scheitern — Platzhalter je item_type, danach Cursor ins Titelfeld
    # (focus_title unten). Bei leerem Platzhalter keine Uniqueness-Prüfung.
    @blank_title  = params[:title].blank?
    default_title = case params[:item_type].to_s
                    when "person"       then "Neue Person"
                    when "organization" then "Neue Organisation"
                    else                     "Neues Wissen"
                    end
    qc_title = params[:title].presence || default_title
    if params[:file].present?
      @item = FileProxy.create_with_file(
        actor:       current_actor,
        title:       qc_title,
        uploaded_io: params.require(:file),
        item_type:   params[:file].content_type.to_s.start_with?("image/") ? :image : :transcript,   # #609 v3
        topics:      split_slugs(params[:topics]),
        contacts:    split_slugs(params[:contacts]),
        tags:        split_slugs(params[:tags])
      )
    else
      @item = FileProxy.create(
        actor:      current_actor,
        title:      qc_title,
        item_type:  params.require(:item_type),
        content:    params.fetch(:content, ""),
        aliases:    params[:aliases].to_s.split(",").map(&:strip).reject(&:blank?),
        topics:     Array(params[:topics].is_a?(String) ? params[:topics].split(/[,\s]+/) : params[:topics]).reject(&:blank?),
        contacts:   Array(params[:contacts].is_a?(String) ? params[:contacts].split(/[,\s]+/) : params[:contacts]).reject(&:blank?),
        tags:       Array(params[:tags].is_a?(String) ? params[:tags].split(/[,\s]+/) : params[:tags]).reject(&:blank?),
        enforce_title_uniqueness: !@blank_title
      )
    end
    apply_bib_source!(@item, bib_source) if bib_source
    apply_locator!(@item)
    apply_person_org!(@item) if @item.item_type.in?(%w[person organization])
    # #761 (Hans): optionale URL im Person-Quick-Add → Kontaktdaten gleich aus
    # der Quelle ziehen (On-Ramp in die Kontaktdaten-Phase der Entitäts-
    # Recherche, wenn die Primärquelle schon vorliegt). Toast hängt unten an
    # die Quick-Create-Streams, damit die frische Card die Daten schon zeigt.
    enrich_toast = enrich_contact_from_url(params[:enrich_url]) if params[:enrich_url].present?
    # #301: Quick-Create aus der Topbar-Leiste — frische KI-/Person-Card
    # direkt an den aktuellen Stack appenden (kein stack_card_new-
    # Placeholder wie beim in_stack-Pfad). blade_stack_container
    # existiert nur auf Stack-Seiten; sonst No-Op.
    if params[:quick_create].present?
      respond_to do |format|
        format.turbo_stream do
          streams = []
          # #484 Increment C (Hans, 2026-06-03): aus einem Topic-Reiter-
          # Eingabeschlitz heraus die frische Row SOFORT oben in die Liste
          # prependen (params[:tab_list] = die <ul>-id, tab_topic = Slug
          # fuer die Row-Verlinkung).
          if params[:tab_list].present?
            streams << turbo_stream.prepend(params[:tab_list],
              partial: "knowledge_items/list_row",
              locals: { item: @item, topic_slug: params[:tab_topic].to_s, work_tree_count: 0 })
          end
          streams << turbo_stream.append("blade_stack_container",
            partial: "knowledge_items/stack_card",
            # #390 (Hans, 2026-05-28): nach Quick-Create direkt in den
            # Beschreibungs-Edit-Mode springen + Cursor ins Feld setzen.
            locals: { item: @item, body_html: load_body_html(@item),
                      # #609: Datei-KI (Bild/PDF) hat keinen editierbaren Body.
                      # #739: ohne Titel → Cursor ins Titelfeld statt in den Body.
                      auto_edit_body: params[:file].blank? && !@blank_title,
                      focus_title:    @blank_title })
          streams << enrich_toast if enrich_toast
          render turbo_stream: streams
        end
        format.html { redirect_to knowledge_items_path(selected: @item.uuid) }
      end
      return
    end
    return render_stack_create_success if params[:in_stack].present?
    redirect_to knowledge_items_path(selected: @item.uuid),
      notice: "Eintrag '#{@item.title}' angelegt."
  rescue ActiveRecord::RecordInvalid => e
    # #202: Dubletten-Titel & andere Validation-Errors freundlich abfangen.
    return render_stack_create_error(e) if params[:in_stack].present?
    redirect_to knowledge_items_path, alert: e.message
  end

  # #609: Bild aus der Zwischenablage (Editor-Paste) — legt eine Bild-KI
  # an und liefert Titel/UUID zurück; das JS fügt ![[Titel]] am Cursor
  # ein. Titel auto-eindeutig (Screenshot + Zeitstempel, Suffix bei
  # Kollision), damit der Embed-Lookup (by_title) eindeutig trifft.
  def paste_image
    file = params.require(:file)
    base = params[:title].presence || "Screenshot #{Time.current.strftime('%Y-%m-%d %H.%M.%S')}"
    title = base
    n = 2
    while KnowledgeItem.by_title_ci(title).exists?
      title = "#{base} (#{n})"
      n += 1
    end
    item = FileProxy.create_with_file(actor: current_actor, title: title,
                                      uploaded_io: file, item_type: :image)   # #609 v3
    render json: { title: item.title, uuid: item.uuid }
  end

  # #608: Bekanntheit manuell togglen — grünes Icon übersteuert das
  # automatische Blau (Kommunikation vorhanden). Pure-DB-Feld (#544),
  # kein Frontmatter-Roundtrip nötig.
  def toggle_personally_known
    @item.update!(personally_known: !@item.personally_known)
    render turbo_stream: turbo_stream.replace("person_known_toggle_#{@item.uuid}",
      partial: "knowledge_items/person_known_toggle", locals: { item: @item })
  end

  # #705 (Hans): Body-Darstellung zwischen Markdown und HTML umschalten.
  # Rendert die Detail-Card neu (Body wechselt zwischen Markdown-Render und
  # sandboxed iframe).
  def toggle_render_mode
    @item.update!(render_mode: @item.render_html? ? "markdown" : "html")
    render_update_detail_stream
  end

  # JSON-Endpoint für die Wikilink-Autocomplete im Edit-Formular.
  # Liefert bis zu 10 Treffer nach Titel-Substring, case-insensitive.
  # #363 (Hans, 2026-05-25): KI-Tag-Suggestions analog
  # TasksController#suggest_tags. Picker fuettert nur das Eingabe-
  # Feld; Add/Remove laeuft ueber KnowledgeItemTagsController.
  def suggest_tags
    # #428 (Hans, 2026-05-31): aus der zentralen Tag-Registry — gemeinsames
    # Vokabular ueber KnowledgeItems UND Tasks hinweg (siehe TasksController).
    tags = Tag.vocabulary(params[:q])
    render json: { items: tags.first(20).map { |t| { slug: t, label: t } } }
  end

  def suggest
    # #667: `[[@Name`-Personen-Autocomplete sendet ein führendes `@` —
    # das gehört zur Wikilink-Syntax, nicht zum Titel. Strippen, sonst
    # findet die Titel-Suche nichts (KI-Titel beginnen nicht mit @).
    q = params[:q].to_s.strip.delete_prefix("@").strip.downcase
    scope = KnowledgeItem.visible_to(current_actor).order(file_updated_at: :desc)
    # type=person+organization → Picker für Erwähnungen filtert auf
    # Person-/Org-KIs (Ersatz für den alten /contacts/suggest).
    if (types = Array(params[:item_type]).flat_map { |t| t.to_s.split(",") }.map(&:strip).reject(&:blank?)).any?
      scope = scope.where(item_type: types)
    end
    if q.present?
      # Title-Substring ODER Alias-Substring — lower(alias) LIKE q via unnest.
      scope = scope.where(
        "LOWER(title) LIKE :q OR EXISTS (SELECT 1 FROM unnest(aliases) a WHERE LOWER(a) LIKE :q)",
        q: "%#{q}%"
      )
    end
    results = scope.limit(10).pluck(:uuid, :title, :aliases)
    # #484 (Hans, 2026-06-03): wenn ein topic gegeben ist, markieren,
    # welche Treffer schon im Topic sind (Picker zeigt den Topic-Farbpunkt).
    in_topic = {}
    if params[:topic].present? && (tp = Topic.find_by(slug: params[:topic]))
      in_topic = tp.knowledge_items.where(uuid: results.map(&:first))
                   .pluck(:uuid).index_with { true }
    end
    # #460 (Hans, 2026-06-04): id_as_uuid → der entity-picker postet
    # item.slug; für den Supersession-Picker muss das die UUID sein (eine
    # KI-Identität, kein parameterisierter Titel). exclude blendet das
    # aktuelle KI aus (kann sich nicht selbst ablösen).
    id_as_uuid = params[:id_as_uuid].present?
    exclude    = params[:exclude].to_s
    items = results.reject { |uuid, _t, _a| uuid == exclude }.map { |uuid, title, aliases|
      { uuid: uuid, title: title, aliases: aliases || [],
        in_topic: in_topic[uuid] || false,
        # `slug`/`label` für den slug-autocomplete-Client (Form-Feld
        # "Kontakte" in /knowledge_items/new), der auf Slug-Strings
        # statt UUIDs schreibt.
        slug:  id_as_uuid ? uuid : title.parameterize,
        label: title }
    }
    render json: { items: items }
  end

  # Soft-Delete — Datei wandert in knowledge/.trash/, Record bekommt
  # deleted_at. Toast mit Undo (POST /knowledge_items/:uuid/restore).
  # Cron räumt nach 30 Tagen hart auf.
  def destroy
    title = @item.title
    uuid  = @item.uuid
    FileProxy.destroy(actor: current_actor, knowledge_item: @item)
    respond_to do |format|
      format.turbo_stream do
        # Stream entfernt Card im Stack + Listen-Row links + zeigt
        # Toast. Wenn ein Target im DOM fehlt: silent fail, kein
        # Schaden.
        render turbo_stream: [
          turbo_stream.remove("stack_card_#{uuid}"),
          turbo_stream.remove("knowledge_row_#{uuid}"),
          helpers.toast_stream(
            message:  "'#{title.truncate(40)}' gelöscht",
            undo_url: restore_knowledge_item_path(uuid: uuid),
            undo_payload: {}
          )
        ]
      end
      format.html { redirect_to knowledge_items_path, notice: "'#{title.truncate(40)}' in den Papierkorb gelegt." }
    end
  end

  def restore
    FileProxy.restore(actor: current_actor, knowledge_item: @item)
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: helpers.toast_stream(
          message: "'#{@item.title.truncate(40)}' wiederhergestellt"
        )
      end
      format.html { redirect_to knowledge_items_path, notice: "Wiederhergestellt." }
    end
  end

  # #460 (Hans, 2026-06-04): Supersession setzen — @item (alt) wird als
  # abgelöst durch successor_uuid (neu) markiert. Re-Export via FileProxy
  # für den git-Commit (Provenienz), dann Detail-Card neu rendern (Banner).
  def supersede
    successor = KnowledgeItem.find_by(uuid: params[:successor_uuid].to_s)
    if successor.nil?
      return render turbo_stream: helpers.toast_stream(message: "KI nicht gefunden"),
                    status: :unprocessable_entity
    end
    @item.mark_superseded_by!(successor, actor: current_actor)
    FileProxy.update(actor: current_actor, knowledge_item: @item)
    render_update_detail_stream
  rescue ArgumentError => e
    render turbo_stream: helpers.toast_stream(message: e.message), status: :unprocessable_entity
  end

  def unsupersede
    @item.clear_supersession!
    FileProxy.update(actor: current_actor, knowledge_item: @item)
    render_update_detail_stream
  end

  def trash
    @discarded = KnowledgeItem.visible_to(current_actor).discarded.order(deleted_at: :desc).limit(100)
  end

  # UUID-Lookup für den Stack-Verlauf-Drawer. Nimmt eine Liste von
  # UUIDs entgegen und liefert pro vorhandenem KI Titel + item_type.
  # Fehlende oder soft-gelöschte UUIDs werden ausgelassen.
  def resolve
    uuids = Array(params[:uuids]).map(&:to_s).reject(&:blank?)
    items = KnowledgeItem.visible_to(current_actor).where(uuid: uuids)
                         .pluck(:uuid, :title, :item_type)
                         .map { |u, t, i| { uuid: u, title: t, item_type: i } }
    render json: { items: items }
  end

  # Obsidian-Verhalten: Klick auf einen ungelösten [[Foo]]-Link legt
  # das Item an. Idempotent — wenn ein Item mit demselben Titel
  # existiert, wird dessen UUID zurückgegeben (kein Duplikat).
  # Antwort: { uuid:, title: } als JSON.
  def wikilink_create
    title = params[:title].to_s.strip
    return render(json: { error: "title required" }, status: :unprocessable_entity) if title.empty?

    existing = KnowledgeItem.by_title_ci(title).first
    if existing
      render json: { uuid: existing.uuid, title: existing.title }
      return
    end

    item = FileProxy.create(
      actor: current_actor, title: title,
      item_type: :note, content: ""
    )
    render json: { uuid: item.uuid, title: item.title }
  end

  # #378 Phase 3 (Hans, 2026-05-26): wrap_highlight wanderte in
  # KnowledgeHighlightsController. URL bleibt via Route-to-Mapping.
  # #378 Phase 4 (Hans, 2026-05-26): request_entity_import +
  # start_wikilink_research wanderten in
  # KnowledgeWikilinkResearchController. URLs bleiben via :to-Mapping.

  # Hängt einen Quote (aus der Zwischenablage) an die "Best-of"-
  # Quotes-Sammlung dieser PDF an. Sammlung-Lookup via Title-Convention
  # `Quotes aus <pdf-title>` plus Backlink zur PDF — bei Nicht-Existenz
  # wird sie angelegt mit Wikilink-Header.
  def quote_from_clipboard
    text = params[:text].to_s
    return render(json: { error: "empty" }, status: :unprocessable_entity) if text.strip.empty?

    collection, created = body_ops.append_quote(text)
    render json: { uuid: collection.uuid, created: created }
  end

  # Streamt die Binär-Datei eines `document`-KI (z.B. PDF) inline,
  # damit der Browser-PDF-Viewer sie im iframe anzeigen kann. Download
  # via `?download=1` erzwingt attachment-Disposition.
  def file
    full_path = FileProxy::BASE_PATH.join(@item.file_path)
    raise ActionController::RoutingError, "not found" unless File.exist?(full_path)
    disposition = params[:download].present? ? "attachment" : "inline"
    send_file full_path,
      type:        Mime::Type.lookup_by_extension(File.extname(full_path).delete(".")) || "application/octet-stream",
      disposition: disposition,
      filename:    File.basename(@item.file_path)
  end

  # `card` und `detail_pane` sind in KnowledgeStackController
  # ausgelagert (#203 Phase E.1).

  # Versions-Verlauf liegt jetzt in KnowledgeVersionsController; die
  # Block-Anchor-Actions (ensure_anchor, comment_at, start_research_at,
  # backlinks) in KnowledgeAnchorsController. Routes zeigen weiterhin
  # auf die alten URL-Pfade — nur die Controller-Klasse ist neu.

  def edit
    @body_markdown = FileProxy.read_body(actor: current_actor, knowledge_item: @item)
    @topic_slugs   = @item.topics.pluck(:slug).join(", ")
    # Erwähnte Person/Org-KIs als parametisierte Slug-Liste — passt zum
    # Slug-Autocomplete im /new-Form und der frontmatter-Kontakte-Liste.
    @contact_slugs = @item.mentioned_kis.map { |k| k.title.parameterize }.join(", ")
  rescue FileProxy::FileNotFound
    redirect_to knowledge_item_path(@item.uuid), alert: "Datei nicht auf Platte gefunden."
  end

  def update
    form = KnowledgeItemUpdateForm.new(params)
    FileProxy.update(actor: current_actor, knowledge_item: @item, **form.to_update_args)
    @item.reload
    # #305: Quelle nachtraeglich verknuepfen oder loesen — fuer alle
    # item_types. Wenn slug leer kommt, wird die Verknuepfung explizit
    # entkoppelt; sonst neu gesetzt. Frontmatter wird mitgezogen.
    if params.key?(:bib_source_slug)
      slug = params[:bib_source_slug].to_s.strip
      if slug.empty?
        if @item.bib_source_id
          @item.update!(bib_source_id: nil)
          FileProxy.merge_frontmatter!(actor: current_actor, knowledge_item: @item, bib_source: nil)
        end
      elsif (new_source = Source.find_by(slug: slug))
        apply_bib_source!(@item, new_source)
      end
      @item.reload
    end
    record_edit_view(@item)
    respond_to do |format|
      format.turbo_stream { render_update_detail_stream }
      format.html         { redirect_to knowledge_item_path(@item.uuid), notice: "Gespeichert." }
    end
  end

  # #541 (Hans, 2026-06-08): USt-Befreiung am Kontakt umschalten — DB-direkt
  # (Source of Truth = DB, kein Frontmatter). Reine Persistenz, kein Re-Render
  # nötig (die Checkbox spiegelt den Zustand bereits clientseitig).
  def vat_exempt
    @item.update_column(:vat_exempt, ActiveModel::Type::Boolean.new.cast(params[:vat_exempt]))
    head :no_content
  end

  # #544 (Hans, 2026-06-08): ID-Nummern (Key-Value, optional mit Gegenseite)
  # direkt in der DB speichern — DB ist Source of Truth, keine Frontmatter-
  # Synchronisation. Ersetzt den ganzen Satz wie der Affiliations-Editor.
  def identifiers
    # #532: Upsert statt destroy/recreate — bestehende Zeilen behalten ihre
    # id (per verstecktem Feld), damit Dokument-Auswahlen (shown_identifier_ids)
    # eine Bearbeitung überleben.
    seen = []
    Array(params[:identifiers]).each_with_index do |row, i|
      row   = row.respond_to?(:permit) ? row.permit(:id, :label, :value, :counterparty).to_h : row.to_h
      label = row["label"].to_s.strip
      value = row["value"].to_s.strip
      next if label.empty? || value.empty?
      cp      = row["counterparty"].to_s.strip
      cp_uuid = cp.present? ? KnowledgeItem.persons_and_orgs.by_title_ci(cp).first&.uuid : nil
      rec = row["id"].present? ? @item.identifiers.find_by(id: row["id"]) : nil
      rec ||= @item.identifiers.new
      rec.assign_attributes(label: label, value: value, counterparty_uuid: cp_uuid, position: i)
      rec.save!
      seen << rec.id
    end
    @item.identifiers.where.not(id: seen).destroy_all
    @item.reload
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to knowledge_item_path(@item.uuid), notice: "IDs gespeichert." }
    end
  end

  # #532 (Hans, 2026-06-08): strukturierte Postadressen DB-direkt speichern
  # (Upsert mit stabilen ids). Eine leere Adresse (alle Felder leer) entfällt.
  def addresses
    seen = []
    Array(params[:addresses]).each_with_index do |row, i|
      row = row.respond_to?(:permit) ? row.permit(:id, :line1, :line2, :postal_code, :city, :country, :billing, :kind).to_h : row.to_h
      attrs = %w[line1 line2 postal_code city country].to_h { |k| [k, row[k].to_s.strip] }
      next if attrs.values.all?(&:blank?)
      rec = row["id"].present? ? @item.postal_addresses.find_by(id: row["id"]) : nil
      rec ||= @item.postal_addresses.new
      rec.assign_attributes(attrs.merge(
        billing: ActiveModel::Type::Boolean.new.cast(row["billing"]) ? true : false,
        kind:    PostalAddress.kinds.key?(row["kind"].to_s) ? row["kind"] : "liegenschaft",  # #622
        position: i))
      rec.save!
      seen << rec.id
    end
    @item.postal_addresses.where.not(id: seen).destroy_all
    @item.reload
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to knowledge_item_path(@item.uuid), notice: "Adresse gespeichert." }
    end
  end

  # #786 (Hans): Bankverbindungen (mehrere) am Person-/Org-KI — Upsert wie
  # #addresses. IBAN/BIC-Normalisierung passiert im Modell (before_save).
  def bank_accounts
    seen = []
    Array(params[:bank_accounts]).each_with_index do |row, i|
      next unless row.respond_to?(:permit) || row.is_a?(Hash)   # leere Array-Artefakte ignorieren
      row = row.respond_to?(:permit) ? row.permit(:id, :iban, :bic, :bank_name, :holder, :label).to_h : row.to_h
      attrs = %w[iban bic bank_name holder label].to_h { |k| [k, row[k].to_s.strip] }
      next if attrs.values.all?(&:blank?)
      rec = row["id"].present? ? @item.bank_accounts.find_by(id: row["id"]) : nil
      rec ||= @item.bank_accounts.new
      rec.assign_attributes(attrs.merge(position: i))
      rec.save!
      seen << rec.id
    end
    @item.bank_accounts.where.not(id: seen).destroy_all
    @item.reload
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to knowledge_item_path(@item.uuid), notice: "Bankverbindung gespeichert." }
    end
  end

  # #761 (Hans, 2026-06-23): Kontaktdaten aus einer URL (Impressum/Kontakt-
  # seite) ziehen und in die LEEREN Felder des Person-/Org-KI übernehmen
  # (bestehende Werte werden nie überschrieben). Bequeme Auslösung der
  # Kontaktdaten-Phase der Entitäts-Recherche, wenn die Primärquelle vorliegt.
  def complete_from_url
    unless @item.item_type.in?(%w[person organization])
      return render turbo_stream: helpers.toast_stream(message: t("knowledge.detail.complete_only_contacts"))
    end
    url   = params[:url].to_s.strip
    added = ContactEnrichment.from_url(item: @item, actor: current_actor, url: url)
    @item.reload
    render turbo_stream: [
      turbo_stream.replace("knowledge_detail_#{@item.uuid}",
        partial: "knowledge_items/detail",
        locals: { item: @item, in_stack: params[:in_stack].present?,
                  mode: :preview, body_html: load_body_html(@item) }),
      helpers.toast_stream(message: added.any? ?
        t("knowledge.detail.complete_added", fields: added.join(", ")) :
        t("knowledge.detail.complete_none"))
    ]
  rescue ContactExtractor::Error => e
    render turbo_stream: helpers.toast_stream(message: t("knowledge.detail.complete_failed", error: e.message))
  end

  private

  # #761 (Hans): Kontaktdaten aus einer URL ziehen und in leere Felder von
  # @item übernehmen; gibt einen fertigen Toast-Stream zurück (oder nil, wenn
  # keine/ungeeignete URL). Geteilt vom Person-Quick-Add (#create) und dem
  # Globus-Icon (#complete_from_url). Merge-Logik: ContactEnrichment (#801 P2).
  def enrich_contact_from_url(url)
    url = url.to_s.strip
    return nil if url.blank?
    return nil unless @item.item_type.in?(%w[person organization])
    added = ContactEnrichment.from_url(item: @item, actor: current_actor, url: url)
    @item.reload
    helpers.toast_stream(message: added.any? ?
      t("knowledge.detail.complete_added", fields: added.join(", ")) :
      t("knowledge.detail.complete_none"))
  rescue ContactExtractor::Error => e
    helpers.toast_stream(message: t("knowledge.detail.complete_failed", error: e.message))
  end

  # Capability-Override pro Custom-Action. Standard (index/show/new/...)
  # mappt der Gated-Concern selbst; hier listen wir nur die Abweichungen.
  ACTION_CAPABILITIES = {
    "restore"               => "update",
    "identifiers"           => "update",
    "addresses"             => "update",
    "complete_from_url"     => "update",
    "trash"                 => "read",
    "resolve"               => "read",
    "wikilink_create"       => "create",
    # request_entity_import legt einen Task an, prüft sonst aber nur
    # den bestehenden KI-Read — capability ist "read" auf KI.
    "request_entity_import"    => "read",
    "start_wikilink_research"  => "read"
  }.freeze

  def controller_action_to_capability
    ACTION_CAPABILITIES[action_name] || super
  end

  def body_ops
    @body_ops ||= KnowledgeItemBodyOps.new(@item, actor: current_actor)
  end

  # ─── Stack-Mode Response-Helfer (#207 Item 1) ─────────────────────
  # in_stack-Branches der Actions new/create/update kennen alle das
  # gleiche Stream-Muster (Card replace + List append). Vorher inline,
  # jetzt private Helfer — die Actions bleiben Single-Path.

  def render_stack_new_card
    render partial: "knowledge_items/stack_new_card",
      locals: { topic_slugs: @default_topic_slugs, default_type: @default_type },
      layout: false
  end

  def render_stack_create_success
    respond_to do |format|
      format.turbo_stream do
        # Placeholder-Card durch echte Card ersetzen + Listen-Row anhaengen.
        # blade-stack-Controller picked die UUID via MutationObserver auf.
        render turbo_stream: [
          turbo_stream.replace("stack_card_new",
            partial: "knowledge_items/stack_card",
            # #445 (Hans, 2026-06-01): Nach dem Anlegen Cursor in die
            # BESCHREIBUNG (content_edit) setzen, nicht ins Antwortfeld —
            # analog zum quick_create-Pfad. auto_edit_body -> der Card-
            # Wrapper bekommt data-focus-after-add="content_edit", das der
            # blade-stack-Controller nach dem (Re)Append fokussiert.
            locals: { item: @item, body_html: load_body_html(@item), auto_edit_body: true }),
          turbo_stream.append("knowledge_list",
            partial: "knowledge_items/list_row",
            locals: { item: @item })
        ]
      end
    end
  end

  def render_stack_create_error(exception)
    flash.now[:alert] = exception.record&.errors&.full_messages&.join(", ").presence ||
                         "Anlegen fehlgeschlagen."
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace("stack_card_new",
          partial: "knowledge_items/stack_new_card",
          locals: {
            topic_slugs:     params[:topics].to_s,
            default_type:    params[:item_type].to_s,
            prefill_title:   params[:title].to_s,
            prefill_content: params[:content].to_s,
            error_message:   flash.now[:alert]
          }), status: :unprocessable_entity
      end
    end
  end

  def render_update_detail_stream
    # `keep_editing=1` (vom Cmd+S-Shortcut): nach dem Speichern zurueck
    # in den Edit-Mode. Sonst wie bisher: Preview mit gerendertem Body.
    locals = { item: @item, in_stack: params[:in_stack].present? }
    if params[:keep_editing].present?
      locals.merge!(mode: :edit,
                    body_markdown: FileProxy.read_body(actor: current_actor, knowledge_item: @item))
    else
      locals.merge!(mode: :preview, body_html: load_body_html(@item))
    end
    render turbo_stream: [
      turbo_stream.replace("knowledge_detail_#{@item.uuid}",
        partial: "knowledge_items/detail", locals: locals)
    ]
  end

  # Resolve-or-create Source aus dem KI-Form.
  # Priorität: new_source[title] gefüllt → Source.create!,
  # sonst bib_source_slug → Source.find_by(slug:). nil wenn beides leer.
  # Wird VOR der KI-Anlage aufgerufen, damit ein Anlage-Fehler die KI
  # gar nicht erst entstehen lässt.
  def resolve_or_create_bib_source!
    new_src = params[:new_source]
    if new_src.is_a?(ActionController::Parameters) && new_src[:title].to_s.strip.present?
      title = new_src[:title].to_s.strip
      # #512 (Hans, 2026-06-04): keinen langen title-Slug mehr setzen — das
      # Modell baut den Citekey `autor_jahr_n` (before_validation).
      Source.create!(
        title:         title,
        csl_type:      new_src[:csl_type].presence || "book",
        url:           new_src[:url].presence,
        issued_string: new_src[:issued_string].presence,
        creator:       current_actor
      )
    elsif (slug = params[:bib_source_slug].to_s.strip).present?
      Source.find_by(slug: slug)
    end
  end

  # Verknüpft die KI mit der Bib-Source: DB-Spalte UND Frontmatter-Key.
  def apply_bib_source!(item, source)
    item.update!(bib_source_id: source.id)
    FileProxy.merge_frontmatter!(actor: current_actor, knowledge_item: item,
                                  bib_source: source.slug)
  end

  # Locator für Quote-Types (Direct/Indirect). Wenn Label oder Wert
  # gesetzt: DB-Spalten + Frontmatter mit ziehen, damit der Roundtrip
  # nach Indexer-Lauf konsistent bleibt.
  def apply_locator!(item)
    label = params[:locator_label].to_s.strip.presence
    value = params[:locator_value].to_s.strip.presence
    return unless label || value
    item.update!(locator_label: label, locator_value: value)
    FileProxy.merge_frontmatter!(actor: current_actor, knowledge_item: item,
                                  locator_label: label, locator_value: value)
  end

  # Person/Org-Spezifika nach create durchschreiben (Vorname/Nachname
  # bzw. parent_org). FileProxy.update kümmert sich um Frontmatter,
  # PersonOrgSync hängt sich an, sodass parent_org per Title oder UUID
  # aufgelöst wird. Wenn keines der Felder gefüllt ist: no-op.
  def apply_person_org!(item)
    fields = {
      first_name: params[:first_name].presence,
      last_name:  params[:last_name].presence,
      parent_org: params[:parent_org].presence
    }.compact
    return unless fields.any?
    FileProxy.update(actor: current_actor, knowledge_item: item, **fields)
  end

  def set_item
    # #602 S1: unsichtbare KIs verhalten sich wie nicht existent (404).
    @item = KnowledgeItem.visible_to(current_actor).find(params[:uuid])
  end

  def set_any_item
    @item = KnowledgeItem.with_discarded.visible_to(current_actor).find(params[:uuid])
  end
end
