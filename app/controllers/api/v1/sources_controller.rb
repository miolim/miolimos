module Api
  module V1
    # #155 Phase 3: Bibliographische Quellen anlegen + listen via API.
    # Schlank gehalten — die Recherche-Agents brauchen Anlegen für ihre
    # Wikilink-Importe; weiterführende Felder (Autoren, Identifier) lassen
    # sich später ergänzen.
    class SourcesController < BaseController
      SOURCE_SERIALIZER = ->(s) do
        {
          slug:            s.slug,
          title:           s.title,
          csl_type:        s.csl_type,
          url:             s.url,
          issued_string:   s.issued_string,
          publisher:       s.publisher,
          container_title: s.container_title,
          abstract:        s.abstract,
          authors:         s.display_authors,
          created_at:      s.created_at,
          updated_at:      s.updated_at
        }
      end

      def index
        scope = Source.all
        if (q = params[:q].to_s.strip).length >= 2
          scope = scope.where("LOWER(title) LIKE ?", "%#{q.downcase}%")
        end
        render_collection(scope.order(:title), serializer: SOURCE_SERIALIZER)
      end

      def show
        render_one(Source.find_by!(slug: params[:slug]), serializer: SOURCE_SERIALIZER)
      end

      # POST /api/v1/sources
      # Pflicht: title. Optional: csl_type (Default: webpage), url, issued_string,
      # publisher, container_title, abstract, slug (sonst auto aus title).
      # #516 (Hans, 2026-06-05): `authors` (Array oder ";"-getrennt) → je Name
      # eine (provisorische) Personen-KI + author-Verknüpfung; danach Citekey-
      # Slug mit dem Autor neu bauen (sofern kein expliziter slug).
      def create
        attrs   = build_attrs
        authors = parse_authors

        Source.transaction do
          @source = Source.create!(attrs.merge(creator: current_actor))
          authors.each { |name| Authorship.attach_by_name(source: @source, name: name, actor: current_actor) }
          if params[:slug].blank? && authors.any?
            @source.reload
            @source.update!(slug: @source.build_citation_slug)
          end
        end

        render_one(@source, serializer: SOURCE_SERIALIZER, status: :created)
      end

      # PATCH /api/v1/sources/:slug — #460 (Hans, 2026-06-04): Metadaten
      # nachpflegen (Recherche-Pflegephase). FLAT-Params, partial — nur
      # übergebene Felder ändern sich.
      # #579 (Hans, 2026-06-10): auch `authors` nachpflegbar — Agenten
      # sollen Titel/Autoren/Jahr strukturiert statt als Zitations-String
      # im Titel erfassen; PATCH hängt fehlende Autoren an (idempotent
      # via Authorship.attach_by_name, entfernt keine).
      UPDATABLE = %w[title csl_type url issued_string publisher container_title abstract].freeze
      def update
        source = Source.find_by!(slug: params[:slug])
        attrs  = UPDATABLE.each_with_object({}) do |k, h|
          h[k] = params[k] if params.key?(k)
        end
        Source.transaction do
          source.update!(attrs)
          parse_authors.each { |name| Authorship.attach_by_name(source: source, name: name, actor: current_actor) }
        end
        render_one(source, serializer: SOURCE_SERIALIZER)
      end

      private

      # `authors` als Array (`authors[]=A&authors[]=B`) oder als ein String
      # mit `;`-Trennung. Leereinträge raus.
      def parse_authors
        Array(params[:authors]).flat_map { |a| a.to_s.split(/\s*;\s*/) }.map(&:strip).reject(&:blank?)
      end

      def build_attrs
        title    = params.require(:title).to_s.strip
        csl_type = params[:csl_type].presence || "webpage"
        # #512 (Hans, 2026-06-04): kein langer title-Slug mehr — ohne
        # expliziten slug-Param baut das Modell den Citekey `autor_jahr_n`
        # (before_validation). slug nur, wenn der Caller ihn vorgibt.
        slug     = params[:slug].presence
        {
          title:           title,
          csl_type:        csl_type,
          slug:            slug,
          url:             params[:url].presence,
          issued_string:   params[:issued_string].presence,
          publisher:       params[:publisher].presence,
          container_title: params[:container_title].presence,
          abstract:        params[:abstract].presence
        }.compact
      end

      def generate_unique_slug(title)
        base = title.parameterize.first(80)
        base = "source-#{SecureRandom.hex(3)}" if base.blank?
        candidate = base
        # Auto-suffix bei Kollision, idempotent für Mehrfachaufrufe mit
        # identischem Titel — Researcher kann erstmal anlegen, später
        # dedupen.
        while Source.exists?(slug: candidate)
          candidate = "#{base}-#{SecureRandom.hex(2)}"
        end
        candidate
      end

      def controller_resource_type
        "Source"
      end
    end
  end
end
