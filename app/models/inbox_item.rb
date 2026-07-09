# Triage-Layer zwischen Quelle (Folder-Watch, Browser-Add-on, Mail …)
# und KI-Erzeugung. Der User sieht in der Inbox-Ansicht, was reingekommen
# ist, wählt einen Processor (oder bestätigt den Auto-Vorschlag) und
# löst die Verarbeitung aus.
class InboxItem < ApplicationRecord
  # #602 S1: sichtbar = eigene Inbox-Items + Items an sichtbaren Topics.
  include VisibleVia
  visible_via join: "InboxItemTopic", join_fk: :inbox_item_id

  belongs_to :creator, class_name: "Actor"

  # Zurück-Verweise: erzeugte KIs/Tasks (Provenance).
  has_many :knowledge_items, dependent: :nullify
  has_many :tasks,           dependent: :nullify

  # #171: vorgepflegte Themen — werden vom Processor an die erzeugten
  # KIs/Tasks weitergereicht.
  has_many :inbox_item_topics, dependent: :destroy
  has_many :topics, through: :inbox_item_topics

  STATUSES      = %w[pending processing awaiting_confirmation processed failed archived].freeze
  SOURCE_KINDS  = %w[youtube_url web_url markdown text upload pdf_upload].freeze

  validates :status,      inclusion: { in: STATUSES }
  validates :source_kind, inclusion: { in: SOURCE_KINDS }

  scope :pending,                -> { where(status: "pending") }
  scope :awaiting_confirmation,  -> { where(status: "awaiting_confirmation") }
  scope :processed,              -> { where(status: "processed") }
  scope :failed,                 -> { where(status: "failed") }
  scope :archived,               -> { where(status: "archived") }
  scope :active,                 -> { where.not(status: "archived") }

  # Auto-Vorschlag: welcher Processor passt zu diesem Item? Wird in der
  # UI als "Run mit X (auto)" angezeigt; User kann übersteuern.
  def suggested_processor_kind
    case source_kind
    when "youtube_url"      then "youtube_transcribe"
    when "web_url"
      # #799: Link auf eine .md-Datei → formattreuer Markdown-Import statt
      # HTML-Clip. #778: TED-Talks haben ein offizielles Transkript → eigener
      # Importer statt Web-Clip (Roh-HTML) oder Whisper (Neu-Transkription).
      if Inbox::Processors::MarkdownUrl.markdown_url?(source_url)      then "markdown_url"
      elsif Inbox::Processors::TedTranscript.ted_talk_url?(source_url) then "ted_transcript"
      else                                                                 "web_clip"
      end
    when "markdown", "text" then "markdown_to_ki"
    when "pdf_upload"
      # #934: E-Mail-Anhänge sind i.d.R. Belege/Anschreiben, keine Literatur —
      # Default Dokument-Eingang. Direkte PDF-Uploads bleiben beim Citavi-
      # Import (Literatur-Workflow, #65); der Picker kann jederzeit übersteuern.
      item_from_email? ? "document_import" : "pdf_bib_import"
    when "upload"
      # #609 v2: Bilder → Bild-KI (vorher fraß der Markdown-Processor
      # das Binärfile und starb an invalid byte sequence).
      Inbox::Processors::ImageToKi.image?(self) ? "image_to_ki" : nil
    end
  end

  # #934: kam dieses Item als E-Mail-Anhang herein (#633)?
  def item_from_email?
    payload["communication_id"].present?
  end

  # Display-Title fallback-Kette für die Liste.
  def display_title
    title.presence ||
      payload["title"].presence ||
      source_url.presence ||
      external_path.to_s.split("/").last.presence ||
      "(ohne Titel)"
  end

  # #755 (Hans, 2026-06-22): Kompakter Titel für Listen/Spine. display_title
  # fällt für URL-Items auf die volle source_url zurück — lange URLs sprengten
  # die Inbox-Zeile und ließen sich eh nicht auf einen Blick unterscheiden.
  # Hier auf <limit> Zeichen mit Ellipse kürzen. Die VOLLE Form (Detail-H1,
  # Edit-Feld, Page-Title) nutzt weiterhin display_title.
  def display_title_short(limit = 50)
    display_title.to_s.truncate(limit)
  end

  # #618 v4: Video-ID aus YouTube-URLs (watch?v=, youtu.be/, shorts/) —
  # fürs Thumbnail (i.ytimg.com braucht keine API). nil bei allem anderen.
  def youtube_video_id
    url = source_url.to_s
    m = url.match(%r{youtube\.com/watch\?(?:[^#]*&)?v=([\w-]{6,})}) ||
        url.match(%r{youtu\.be/([\w-]{6,})}) ||
        url.match(%r{youtube\.com/shorts/([\w-]{6,})})
    m && m[1]
  end

  # #670 (Hans, 2026-06-13): Dublettenkontrolle. Sucht bereits
  # importierte KIs zur selben Quelle. YouTube: über die Source
  # `yt-<videoid>` (slug ODER YouTube-Identifier — robust gegen
  # watch/youtu.be/shorts-Varianten); sonst über die exakte source_url
  # der bibliografischen Quelle. Liefert sichtbare, nicht-verworfene KIs.
  def potential_duplicate_kis
    src = duplicate_source
    return KnowledgeItem.none unless src
    KnowledgeItem.where(bib_source_id: src.id)
  end

  # Die Source, an der eine Dublette hängen würde (für den direkten Link).
  def duplicate_source
    if (vid = youtube_video_id)
      Source.find_by(slug: "yt-#{vid}".downcase) ||
        Source.joins(:source_identifiers)
              .find_by(source_identifiers: { scheme: "YouTube", value: vid })
    elsif source_url.present?
      Source.find_by(url: source_url)
    end
  end

  def potential_duplicate?
    potential_duplicate_kis.exists?
  end
end
