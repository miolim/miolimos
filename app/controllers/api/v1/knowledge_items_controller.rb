module Api
  module V1
    class KnowledgeItemsController < BaseController
      ITEM_SERIALIZER = ->(k) do
        {
          uuid: k.uuid, title: k.title, item_type: k.item_type,
          bib_source_slug: k.bib_source&.slug,
          file_path: k.file_path, content_hash: k.content_hash,
          file_created_at: k.file_created_at, file_updated_at: k.file_updated_at,
          indexed_at: k.indexed_at, created_at: k.created_at, updated_at: k.updated_at,
          superseded_by_uuid: k.superseded_by_uuid, superseded_at: k.superseded_at,
          orcid: k.orcid,
          # #708 (Hans): Kontaktdaten von Personen/Organisationen mitliefern —
          # bisher sah der Agent Adresse/Telefon/IDs nicht und meldete „keine
          # Adresse". Bei Nicht-Personen sind die Arrays leer.
          postal_addresses: k.postal_addresses.map { |a|
            { kind: a.kind, line1: a.line1, line2: a.line2.presence,
              postal_code: a.postal_code, city: a.city,
              country: a.country.presence, billing: a.billing } },
          contact_points: k.contact_points.map { |c|
            { kind: c.kind, label: c.label.presence, value: c.value } },
          identifiers: k.identifiers.map { |i|
            { label: i.label, value: i.value } }
        }
      end

      # #325 (Hans, 2026-05-24): `q` (case-insensitive Title-Substring)
      # + `title` (exakter Match) ergaenzt, damit der Builder-Agent
      # einem Wikilink `[[Title]]` folgen kann ohne Pagination-Bingo.
      def index
        # #708: Kontakt-Assoziationen preloaden — der Serializer liefert sie
        # jetzt mit (sonst N+1 über die Liste).
        scope = visible(KnowledgeItem).where(deleted_at: nil)
                  .includes(:postal_addresses, :contact_points, :identifiers)
        scope = scope.where(item_type: params[:item_type]) if params[:item_type].present?
        if params[:topic_slug].present?
          scope = scope.joins(:topics).where(topics: { slug: params[:topic_slug] })
        end
        if params[:title].present?
          scope = scope.where("LOWER(title) = ?", params[:title].to_s.downcase)
        elsif params[:q].present?
          scope = scope.where("LOWER(title) LIKE ?", "%#{params[:q].to_s.downcase}%")
        end
        render_collection(scope.order(:title), serializer: ITEM_SERIALIZER)
      end

      # #325 (Hans): bei `?include=body` zusaetzlich den Body
      # mitliefern, damit ein Wikilink-Follow ein Request statt zwei
      # ist.
      def show
        item = visible(KnowledgeItem).find(params[:uuid])
        payload = ITEM_SERIALIZER.call(item)
        if params[:include].to_s.include?("body")
          payload[:body] = item.body
        end
        render json: { data: payload }
      end

      def create
        item = FileProxy.create(
          actor:     current_actor,
          title:     params.require(:title),
          item_type: params.require(:item_type),
          content:   params.fetch(:content, ""),
          topics:    Array(params[:topics]),
          contacts:  Array(params[:contacts]),
          tags:      Array(params[:tags])
        )
        render_one(item, serializer: ITEM_SERIALIZER, status: :created)
      end

      # #460 (Hans, 2026-06-04): KI-Update via API. Bislang konnte ein
      # rein per Bearer-Token operierender Agent KIs nur ANLEGEN, nie
      # revidieren — das brach „Versionierung statt Überschreibung" und
      # die Pflege-Phase der KI-Erstellung. FLAT-Params, alle optional;
      # nur übergebene Felder werden geändert (Partial-Update). Body geht
      # über FileProxy.update, das Frontmatter und Datei-Spiegel mitzieht.
      def update
        item = KnowledgeItem.find(params[:uuid])

        # #460: Supersession (Achse B) — superseded_by_uuid setzen/leeren.
        # Erst die Spalte, dann (über FileProxy.update unten) re-exportieren
        # + committen, damit die Ablösung in der git-Historie steht.
        if params.key?(:superseded_by_uuid)
          sb = params[:superseded_by_uuid].to_s.strip
          if sb.empty?
            item.clear_supersession!
          else
            successor = KnowledgeItem.find_by(uuid: sb)
            raise ActiveRecord::RecordNotFound, "successor not found" unless successor
            item.mark_superseded_by!(successor, actor: current_actor)
          end
        end

        args = {}
        args[:title]     = params[:title]           if params.key?(:title)
        args[:content]   = params[:content]         if params.key?(:content)
        args[:item_type] = params[:item_type]       if params.key?(:item_type)
        args[:topics]    = Array(params[:topics])   if params.key?(:topics)
        args[:tags]      = Array(params[:tags])     if params.key?(:tags)
        args[:contacts]  = Array(params[:contacts]) if params.key?(:contacts)
        args[:aliases]   = Array(params[:aliases])  if params.key?(:aliases)
        args[:orcid]     = params[:orcid]           if params.key?(:orcid)   # #516

        # #708 (Hans): Personen-Kontaktdaten (Adresse/Telefon/IDs) pflegen.
        apply_contact_data!(item)

        # Re-Export + Commit, wenn Body/Frontmatter ODER die Supersession
        # sich geändert hat (Letztere ändert das Export-Frontmatter).
        if args.any? || params.key?(:superseded_by_uuid)
          FileProxy.update(actor: current_actor, knowledge_item: item, **args)
        end
        render_one(item.reload, serializer: ITEM_SERIALIZER)
      rescue ArgumentError, ActiveRecord::RecordInvalid => e
        render json: { error: e.message, code: "invalid" }, status: :unprocessable_entity
      end

      # #460 (Hans, 2026-06-04): Soft-Delete via API (Datei wandert in
      # den Papierkorb, deleted_at gesetzt — Restore ist die Inverse im
      # Web). Antwort: das gelöschte Item mit deleted_at.
      def destroy
        item = KnowledgeItem.find(params[:uuid])
        FileProxy.destroy(actor: current_actor, knowledge_item: item)
        render_one(item.reload, serializer: ITEM_SERIALIZER)
      end

      # #516 (Hans, 2026-06-05): Personen-KIs zusammenführen — Dublette in
      # target mergen (Quellen-Autorschaft umhängen + Dublette ablösen).
      def merge_into
        duplicate = KnowledgeItem.find(params[:uuid])
        target    = KnowledgeItem.find_by(uuid: params.require(:target_uuid).to_s)
        raise ActiveRecord::RecordNotFound, "target not found" unless target
        Authorship.merge_persons(duplicate, target, actor: current_actor)
        render_one(duplicate.reload, serializer: ITEM_SERIALIZER)
      rescue ArgumentError => e
        render json: { error: e.message, code: "invalid" }, status: :unprocessable_entity
      end

      def content
        item = KnowledgeItem.find(params[:uuid])
        body = FileProxy.read(actor: current_actor, knowledge_item: item)
        render json: { data: { uuid: item.uuid, content: body } }
      rescue FileProxy::FileNotFound
        render json: { error: "File missing on disk", code: "file_not_found" }, status: :not_found
      end

      # #460 (Hans, 2026-06-04): Edit-Historie (git) eines KI lesen —
      # Achse A der Versionierung, jetzt API-seitig einsehbar.
      def history
        item    = KnowledgeItem.find(params[:uuid])
        commits = KiHistory.for_path(item.file_path, limit: [params.fetch(:limit, 50).to_i, 200].min)
        render json: {
          data: commits.map { |c|
            { sha: c.sha, short_sha: c.short_sha, date: c.date.iso8601,
              author: c.author, subject: c.subject }
          },
          meta: { uuid: item.uuid }
        }
      end

      # Body einer früheren Fassung: GET …/version?sha=<sha>
      def version
        item = KnowledgeItem.find(params[:uuid])
        sha  = params.require(:sha).to_s
        raw  = KiHistory.show(item.file_path, sha)
        if raw.blank?
          render json: { error: "Version leer oder Pfad zur Zeit anders (Rename)", code: "version_empty" },
                 status: :not_found
          return
        end
        _fm, body = MarkdownFrontmatter.parse(raw)
        render json: { data: { uuid: item.uuid, sha: sha, content: body } }
      end

      # Eine alte Fassung wiederherstellen: POST …/restore_version {sha}.
      # Schreibt den damaligen Body via FileProxy.update zurück — ein
      # NEUER Commit, die Historie bleibt vollständig.
      def restore_version
        item = KnowledgeItem.find(params[:uuid])
        sha  = params.require(:sha).to_s
        raw  = KiHistory.show(item.file_path, sha)
        if raw.blank?
          render json: { error: "Version leer — Restore nicht möglich", code: "version_empty" },
                 status: :unprocessable_entity
          return
        end
        fm, body = MarkdownFrontmatter.parse(raw)
        FileProxy.update(actor: current_actor, knowledge_item: item,
                         content: body, title: fm["title"].presence || item.title)
        render_one(item.reload, serializer: ITEM_SERIALIZER)
      end

      # Append-Endpoint für den Chat-Sicherungs-Workflow.
      #
      # Body-Variante 1 — selber Parser wie File-Drop-Importer:
      #   { "content": "<vollständige MD inkl. Frontmatter ODER Light-Header>" }
      #
      # Body-Variante 2 — Felder explizit:
      #   { "content": "<reiner MD-Body>", "title": "...", "source_url": "...", ... }
      #   Importer-Parser bekommt einen synthetisierten Light-Header obendrauf.
      #
      # Match-Hierarchie wie der File-Drop-Importer: append_to → source_url
      # → title → neu. Antwort enthält das (neue oder ergänzte) Item plus
      # `meta.outcome = "created" | "appended"`.
      def append
        raw = params.require(:content).to_s
        raw = inject_overrides_into_light_header(raw, params) if any_override?(params)

        importer = WikiImporter.new(actor: current_actor)
        fm, body = importer.send(:parse, raw)
        target   = importer.send(:lookup_target, fm)

        if target
          session_at = importer.send(:parse_date, fm["created_at"]) ||
                       importer.send(:parse_date, params[:session_at]) ||
                       Date.current
          FileProxy.append_session(
            actor:             current_actor,
            knowledge_item:    target,
            addendum:          body.strip,
            session_at:        session_at,
            frontmatter_merge: { topics: Array(fm["topics"]), tags: Array(fm["tags"]) }
          )
          render json: { data: ITEM_SERIALIZER.call(target.reload),
                         meta: { outcome: "appended" } }
        else
          chat_title = (fm["chat_title"].presence || params[:chat_title]).to_s.strip.presence
          title = (fm["title"].presence || params[:title] || chat_title).to_s.strip
          if title.empty?
            render json: { error: "title required for new item" },
                   status: :unprocessable_entity
            return
          end
          item = FileProxy.create(
            actor:      current_actor,
            title:      title,
            item_type:  :abstract,
            content:    body.strip,
            topics:     Array(fm["topics"]),
            contacts:   [],
            tags:       Array(fm["tags"]).presence || ["chat"]
          )
          # Source-Upsert + Verknüpfung — analog zum WikiImporter, damit
          # source_url/chat_title nicht mehr ans KI hängen.
          importer.send(:link_source!, item, fm)
          render json: { data: ITEM_SERIALIZER.call(item),
                         meta: { outcome: "created" } }, status: :created
        end
      end

      private

      # #708 (Hans): Personen-/Org-Kontaktdaten per API pflegen. Replace-
      # Semantik je Feld (nur wenn der Key gesendet wird): der Agent liest
      # erst die aktuelle Liste (kommt seit #708 in der Serialisierung mit),
      # mergt und schreibt die volle Liste zurück. Pure-DB (#544), kein
      # Frontmatter/Export. Atomar pro Item.
      def apply_contact_data!(item)
        keys = %i[postal_addresses contact_points identifiers].select { |k| params.key?(k) }
        return if keys.empty?

        item.transaction do
          if params.key?(:postal_addresses)
            item.postal_addresses.destroy_all
            Array(params[:postal_addresses]).each_with_index do |a, i|
              # kind ist Enum (liegenschaft|post); nur setzen wenn angegeben,
              # sonst greift der Default. Ungültige Werte → ArgumentError → 422.
              attrs = { line1: a[:line1], line2: a[:line2], postal_code: a[:postal_code],
                        city: a[:city], country: a[:country],
                        billing: a[:billing].present?, position: i }
              attrs[:kind] = a[:kind] if a[:kind].present?
              item.postal_addresses.create!(attrs)
            end
          end
          if params.key?(:contact_points)
            item.contact_points.destroy_all
            Array(params[:contact_points]).each_with_index do |c, i|
              item.contact_points.create!(
                kind: c[:kind], label: c[:label].presence, value: c[:value],
                billing: c[:billing].present?, position: i)
            end
          end
          if params.key?(:identifiers)
            item.identifiers.destroy_all
            Array(params[:identifiers]).each_with_index do |d, i|
              item.identifiers.create!(
                label: d[:label], value: d[:value],
                counterparty_uuid: d[:counterparty_uuid].presence, position: i)
            end
          end
        end
      end

      OVERRIDE_PARAMS = %w[title chat_title source source_url append_to topics tags].freeze

      def any_override?(p)
        OVERRIDE_PARAMS.any? { |k| p[k].present? }
      end

      def inject_overrides_into_light_header(raw, p)
        prefix = OVERRIDE_PARAMS.filter_map do |k|
          v = p[k]
          next if v.blank?
          v = Array(v).join(", ") if k.in?(%w[topics tags]) && v.is_a?(Array)
          # Light-Header-Key: underscores → bindestriche, dann Capitalize
          # je Wortteil ("chat_title" → "Chat-Title").
          key = k.tr("_", "-").split("-").map(&:capitalize).join("-")
          "#{key}: #{v}"
        end.join("\n")
        prefix.empty? ? raw : "#{prefix}\n\n#{raw}"
      end

      def controller_action_to_capability
        return "read"   if action_name.in?(%w[content history version])
        return "create" if action_name == "append"
        return "update" if action_name.in?(%w[restore_version merge_into])
        super
      end
    end
  end
end
