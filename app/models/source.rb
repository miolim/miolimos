# Bibliographische Quelle. CSL-JSON-aligned (https://github.com/citation-style-language/schema)
# damit Export nach BibLaTeX/RIS und Pandoc-Pipeline später trivial ist.
# Eine Quelle wird einmal gepflegt, von beliebig vielen KIs (über
# `knowledge_items.source_id`) referenziert.
class Source < ApplicationRecord
  belongs_to :creator, class_name: "Actor"
  belongs_to :parent_source, class_name: "Source", optional: true
  has_many :child_sources, class_name: "Source", foreign_key: :parent_source_id,
    dependent: :nullify

  has_many :source_identifiers, dependent: :destroy
  has_many :source_creators, -> { order(:position, :id) }, dependent: :destroy

  # Personen/Orgs als Author/Editor/etc. — über die KI-uuid.
  has_many :creator_kis, through: :source_creators, source: :knowledge_item

  # KIs, die diese Quelle zitieren.
  has_many :knowledge_items, foreign_key: :bib_source_id, dependent: :nullify

  has_many :task_sources, dependent: :destroy
  has_many :tasks, through: :task_sources

  # #155 Phase 5c: Recherche-Verknuepfung mit Relevanz-Markierung.
  has_many :source_topics, dependent: :destroy
  has_many :research_topics, through: :source_topics, source: :topic

  # CSL-Item-Types (Auszug der häufigsten — komplette Liste siehe
  # https://github.com/citation-style-language/schema/blob/master/schemas/styles/csl-types.rng).
  CSL_TYPES = %w[
    article
    article-journal
    article-magazine
    article-newspaper
    book
    chapter
    legal_case
    legislation
    manuscript
    motion_picture
    paper-conference
    patent
    personal_communication
    podcast
    post
    post-weblog
    report
    review
    software
    speech
    thesis
    webpage
    dataset
    interview
    broadcast
    ai_conversation
  ].freeze

  validates :slug,     presence: true, uniqueness: true,
    format: { with: /\A[a-z0-9]+(?:[-._][a-z0-9]+)*\z/, message: "lowercase, hyphens, dots, underscores" }
  validates :title,    presence: true
  validates :csl_type, inclusion: { in: CSL_TYPES }

  # #198: Citation-Key-Stil — wenn beim Speichern kein Slug gesetzt
  # ist, leiten wir ihn aus Author + Year ab (max 25 Zeichen, à la
  # Zoteros BetterBibTeX). Bestehende Slugs werden nicht angetastet.
  before_validation :generate_slug_if_blank, on: :create

  private

  def generate_slug_if_blank
    return if slug.present?
    self.slug = build_citation_slug
  end

  # #512 (Hans, 2026-06-04): Citekey-Slug `autor_jahr_n` statt langem
  # title.parameterize. Autor = Nachname des Primär-Autors (sonst erstes
  # Titelwort), Jahr aus issued, n = laufende Nummer pro autor_jahr. Beispiel:
  # `bjork_1994_1`. Slugs sind stabil — nur bei Neuanlage erzeugt.
  def build_citation_slug(max_length: 40)
    last = primary_author_last_name.presence || title.to_s.split.first.to_s
    last = ActiveSupport::Inflector.transliterate(last.to_s.downcase).gsub(/[^a-z0-9]/, "")
    last = "quelle" if last.blank?
    last = last[0, max_length - 8] if last.length > max_length - 8
    year = display_year.presence || "nd"
    prefix = "#{last}_#{year}"
    n = 1
    candidate = "#{prefix}_#{n}"
    while Source.where(slug: candidate).where.not(id: id).exists?
      n += 1
      candidate = "#{prefix}_#{n}"
    end
    candidate
  end

  def primary_author_last_name
    creator = source_creators.find { |c| %w[author court].include?(c.role) }
    creator&.knowledge_item&.last_name || creator&.knowledge_item&.title.to_s.split.last
  end

  # #516: Citekey on demand — z.B. um den Slug nach dem Verknüpfen eines
  # Autors neu zu bauen (SourcesController#create).
  public :build_citation_slug

  public

  # #578: EINE Quelle für die Autoren-KIs der Anzeige-Methoden. Nutzt die
  # geladene Assoziation, wenn der Caller `includes(:creator_kis)` bzw.
  # `includes(source_creators: :knowledge_item)` vorgeladen hat — vorher
  # feuerten display_authors/display_authors_list IMMER frische Queries
  # (N+1 pro Listenzeile, pro Autor).
  def author_kis
    if source_creators.loaded?
      # Through-Preload (`includes(:creator_kis)`) lädt die KIs am SOURCE,
      # nicht an den einzelnen source_creators — daher über die UUID-Map
      # zuordnen statt c.knowledge_item (das wäre wieder 1 Query/Autor).
      by_uuid = association(:creator_kis).loaded? ? creator_kis.index_by(&:uuid) : nil
      source_creators.select { |c| %w[author court].include?(c.role) }
                     .sort_by { |c| c.position.to_i }
                     .map { |c| by_uuid ? by_uuid[c.knowledge_item_uuid] : c.knowledge_item }
                     .compact
    else
      source_creators.where(role: %w[author court]).order(:position)
                     .includes(:knowledge_item).map(&:knowledge_item).compact
    end
  end

  # Author/Editor-Liste als joined String — für Listen-Anzeige.
  def display_authors
    authors = author_kis
    return "" if authors.empty?
    names = authors.first(3).map(&:display_name)
    extra = authors.size > 3 ? " et al." : ""
    names.join(", ") + extra
  end

  # #198: Max 3 Personen, „Nachname, Vorname" pro Eintrag, mit „ | "
  # getrennt. Fällt für Nicht-Personen-KIs (Organisationen, „court")
  # auf den Title zurück.
  def display_authors_list
    creators = author_kis
    return "" if creators.empty?
    formatted = creators.first(3).map do |ki|
      if ki.person? && ki.last_name.present?
        first = ki.first_name.to_s.strip
        first.present? ? "#{ki.last_name}, #{first}" : ki.last_name.to_s
      else
        ki.title.to_s
      end
    end
    extra = creators.size > 3 ? " | …" : ""
    formatted.join(" | ") + extra
  end

  def display_year
    issued_date&.year&.to_s || issued_string.to_s.scan(/\d{4}/).first
  end

  # #198: Lokalisiertes Label für den CSL-Type. Fällt auf den Code
  # zurück, falls keine Übersetzung gepflegt ist.
  def csl_type_label
    I18n.t("sources.csl_types.#{csl_type}", default: csl_type.to_s.humanize)
  end

  # CSL-konforme JSON-Struktur. Wird in V2 für Export benutzt.
  def to_csl_json
    {
      "id"               => slug,
      "type"             => csl_type,
      "title"            => title,
      "container-title"  => container_title,
      "publisher"        => publisher,
      "publisher-place"  => publisher_place,
      "issued"           => csl_date(issued_date, issued_string),
      "accessed"         => csl_date(accessed),
      "edition"          => edition,
      "volume"           => volume,
      "issue"            => issue,
      "page"             => pages,
      "abstract"         => abstract,
      "language"         => language,
      "archive"          => archive,
      "archive_location" => archive_location,
      "URL"              => url,
      "jurisdiction"     => jurisdiction,
      "authority"        => court,
      "number"           => docket_number,
      "DOI"              => identifier_value("DOI"),
      "ISBN"             => identifier_value("ISBN"),
      "ISSN"             => identifier_value("ISSN"),
      "PMID"             => identifier_value("PMID"),
      "author"           => csl_creators("author")
    }.compact
  end

  def identifier_value(scheme)
    source_identifiers.find { |i| i.scheme == scheme }&.value
  end

  private

  def csl_date(date, fallback = nil)
    return { "raw" => fallback } if date.nil? && fallback.present?
    return nil if date.nil?
    parts = [date.year, date.month, date.day].compact
    { "date-parts" => [parts] }
  end

  def csl_creators(role)
    source_creators.where(role: role).includes(:knowledge_item).map do |sc|
      ki = sc.knowledge_item
      next unless ki
      if ki.person?
        { "family" => ki.last_name.to_s.presence, "given" => ki.first_name.to_s.presence }.compact
      else
        { "literal" => ki.title }
      end
    end.compact
  end
end
