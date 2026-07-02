require "yaml"
require "fileutils"
require "pathname"

# Verarbeitet Markdown-Dateien aus einer Inbox (~/miolimos-inbox/ per
# Default) und übergibt sie ans Knowledge-System.
#
# Eingabe-Toleranz:
#   - vollständiges YAML-Frontmatter (`---` … `---`) → wird übernommen
#   - Light-Header (erste 5–10 Zeilen mit "Titel: …\nDatum: …\n…") →
#     wird zu Frontmatter konvertiert
#   - gar nichts → Filename als Title, Defaults
#
# Routing per Match-Hierarchie:
#   1. append_to: <uuid>      → exakt
#   2. source_url: <url>      → KI mit gleicher source_url
#   3. title: "<text>"        → KI mit gleichem Title (case-insens.)
#   4. nichts → neues Item anlegen
#
# Bei Match: ruft FileProxy.append_session auf, löscht die Inbox-Datei.
# Bei Neu: ergänzt fehlendes Frontmatter (UUID, type), verschiebt
# die Datei nach knowledge/ai-chats/.
class WikiImporter
  # Inbox liegt per Default als inbox/-Sub-Verzeichnis innerhalb des
  # miolimOS-Daten-Verzeichnisses (konsistent mit MIOLIMOS_DATA_PATH).
  # Override mit MIOLIMOS_INBOX_PATH, wenn die Inbox woanders hin soll
  # (z.B. ein Cloud-Sync-Mount, der nicht im git-Repo lebt).
  def self.default_inbox_path
    base = ENV["MIOLIMOS_INBOX_PATH"]
    return Pathname.new(File.expand_path(base)) if base.present?
    data = ENV.fetch("MIOLIMOS_DATA_PATH", "~/miolimos")
    Pathname.new(File.expand_path(data)).join("inbox")
  end

  INBOX_PATH = default_inbox_path

  Result = Struct.new(:file, :outcome, :item, :error, keyword_init: true) do
    def to_s
      "#{outcome.to_s.upcase}: #{file.basename}#{" → #{item&.title}" if item}#{" (#{error})" if error}"
    end
  end

  # Light-Header-Keys, case-insensitiv. Je Sprache mehrere Aliasse.
  LIGHT_KEYS = {
    "title"      => %w[title titel],
    "chat_title" => %w[chat_title chat-titel chattitel],
    "created_at" => %w[date datum],
    "source_url" => %w[url quelle source-url],
    "bib_source" => %w[bib_source bib-source quelle-slug source-slug],
    "topics"     => %w[topics themen thema],
    "tags"       => %w[tags schlagworte schlagwörter],
    "append_to"  => %w[append-to ergaenze ergänze]
  }.freeze

  def self.run(actor:)
    new(actor: actor).run
  end

  def initialize(actor:, inbox: INBOX_PATH)
    @actor = actor
    @inbox = Pathname.new(inbox)
  end

  def run
    ensure_inbox_dir!
    files = @inbox.glob("*.md").sort
    files.map { |file| process(file) }
  end

  # Stellt sicher, dass die Inbox als Verzeichnis existiert. Klare
  # Fehlermeldung, wenn an dem Pfad versehentlich eine Datei liegt.
  # Legt zusätzlich eine .gitignore an, damit transient inbox-Dateien
  # nicht versehentlich ins miolimos-Daten-Repo committed werden, falls
  # die Inbox im git-tree liegt.
  def ensure_inbox_dir!
    if @inbox.exist? && !@inbox.directory?
      raise "Inbox-Pfad #{@inbox} existiert, ist aber eine Datei statt eines Verzeichnisses. " \
            "Bitte die Datei löschen (oder umbenennen), dann erneut versuchen."
    end
    FileUtils.mkdir_p(@inbox) unless @inbox.exist?
    gi = @inbox.join(".gitignore")
    File.write(gi, "*\n!.gitignore\n") unless gi.exist?
  end

  def process(file)
    raw = file.read
    fm, body = parse(raw)

    target = lookup_target(fm)

    if target
      append_to_existing(file, target, fm, body)
    else
      create_new(file, fm, body)
    end
  rescue ActiveRecord::RecordInvalid => e
    # Detail aus den Validation-Errors ziehen — die generische
    # RecordInvalid-Message ist ohne Feld-Kontext nutzlos.
    detail = e.record&.errors&.full_messages&.join("; ").presence || e.message
    Rails.logger.warn("WikiImporter: validation failed on #{file}: #{detail}")
    Result.new(file: file, outcome: :error, error: "Validierung: #{detail}")
  rescue => e
    Rails.logger.warn("WikiImporter: #{e.class} on #{file}: #{e.message}\n#{e.backtrace.first(5).join("\n")}")
    Result.new(file: file, outcome: :error, error: "#{e.class}: #{e.message}")
  end

  private

  def append_to_existing(file, item, fm, body)
    session_at = parse_date(fm["created_at"]) || Date.current
    FileProxy.append_session(
      actor:             @actor,
      knowledge_item:    item,
      addendum:          body.strip,
      session_at:        session_at,
      # Topics aus Chat-Frontmatter werden als TAGS gemerged: Themen
      # in miolimOS sind Prozess-Einheiten und werden manuell gepflegt.
      # Beim Import landet alles in Tags (Inhalts-Labels).
      frontmatter_merge: { tags: tags_from_chat_fm(fm) }
    )
    file.delete
    Result.new(file: file, outcome: :appended, item: item)
  end

  def create_new(file, fm, body)
    chat_title = fm["chat_title"].to_s.strip.presence
    title  = fm["title"].to_s.strip.presence || chat_title || derive_title(file, body)
    session_at = parse_date(fm["created_at"]) || Date.current
    content = ensure_session_heading(body, session_at)
    item = FileProxy.create(
      actor:      @actor,
      title:      title,
      item_type:  :abstract,
      content:    content,
      # Topics werden NICHT automatisch beim Chat-Import vergeben —
      # in miolimOS sind Themen Prozess-Einheiten, die manuell
      # gepflegt werden. Inhalts-Labels gehen in Tags.
      topics:     [],
      contacts:   slugify(fm["contacts"]),
      tags:       tags_from_chat_fm(fm)
    )
    link_source!(item, fm)
    file.delete
    Result.new(file: file, outcome: :created, item: item)
  rescue ActiveRecord::RecordInvalid => e
    # Idempotenz: file_path:taken bedeutet ein vorheriger Run hat das
    # Item schon angelegt (z.B. abgebrochen vor dem Topic-Linking).
    if e.record.is_a?(KnowledgeItem) && e.record.errors.added?(:file_path, :taken)
      existing = KnowledgeItem.find_by(file_path: e.record.file_path)
      raise unless existing
      slugify(fm["contacts"]).each do |slug|
        ki = PersonKiResolver.find_or_create!(slug, actor: @actor)
        next unless ki
        next if ki.uuid == existing.uuid
        existing.knowledge_item_mentions.find_or_create_by!(mentioned_uuid: ki.uuid)
      end
      file.delete
      Result.new(file: file, outcome: :resumed, item: existing)
    else
      raise
    end
  end

  # Tags-Liste aus Chat-Frontmatter: tags + topics (KI-getippt) werden
  # gemerged. "chat" als Default, falls beide leer.
  def tags_from_chat_fm(fm)
    raw = Array(fm["tags"]) + Array(fm["topics"])
    cleaned = raw.map { |v| v.to_s.strip }.reject(&:blank?).uniq
    cleaned.empty? ? ["chat"] : cleaned
  end

  # Slug-Validation für Contacts: lowercase + bindestrich.
  def slugify(values)
    Array(values).map { |v| v.to_s.parameterize }.reject(&:blank?)
  end

  # Wenn der Body kein `## Session …`-Heading hat, setzen wir
  # selbständig eines voraus — damit ist die TOC-Anzeige im UI
  # konsistent: jede Notiz hat mindestens eine "Session" als Anker.
  def ensure_session_heading(body, session_at)
    text = body.to_s.strip
    return text if text.match?(/^##\s+Session\s+\d{4}-\d{2}-\d{2}/)
    "## Session #{session_at.strftime('%Y-%m-%d')}\n\n#{text}"
  end

  # Match-Hierarchie (nach Verlagerung von source_url/chat_title auf
  # die Source-Ebene):
  #   1. append_to: <uuid>     — exakte KI-UUID
  #   2. bib_source: <slug>    — KI an dieser Source (häufigster Fall
  #                              für Chat-Sicherungen)
  #   3. source_url: <url>     — Source mit dieser url → deren KI
  #   4. chat_title: <text>    — Source mit diesem title → deren KI
  #                              (csl_type personal_communication)
  #   5. title: <text>         — miolimOS-Title (Fallback, kann editiert
  #                              worden sein, daher unsicherer)
  def lookup_target(fm)
    if (uuid = fm["append_to"].to_s.strip).present?
      return KnowledgeItem.find_by(uuid: uuid)
    end
    if (slug = fm["bib_source"].to_s.strip).present?
      hit = KnowledgeItem.where(bib_source: Source.where(slug: slug))
                         .order(file_updated_at: :desc).first
      return hit if hit
    end
    if (url = fm["source_url"].to_s.strip).present?
      hit = KnowledgeItem.where(bib_source: Source.where(url: url))
                         .order(file_updated_at: :desc).first
      return hit if hit
    end
    if (chat_title = fm["chat_title"].to_s.strip).present?
      hit = KnowledgeItem.where(bib_source: Source.where(csl_type: "personal_communication")
                                                  .where("lower(title) = ?", chat_title.downcase))
                         .order(file_updated_at: :desc).first
      return hit if hit
    end
    if (title = fm["title"].to_s.strip).present?
      hit = KnowledgeItem.by_title_ci(title)
                         .order(file_updated_at: :desc).first
      return hit if hit
    end
    nil
  end

  # Frontmatter-Parser mit Light-Mode-Fallback.
  def parse(content)
    if content.start_with?("---")
      data, body = MarkdownFrontmatter.parse(content)
      return [data, body] unless data.empty? && body == content
    end

    # Light-Header: scanne erste Zeilen nach Key: Value, stoppe bei
    # erstem Heading / Leerzeile-direkt-nach-Headers / Markdown-Block.
    fm   = {}
    rest_starts_at = 0
    lines = content.lines
    lines.each_with_index do |line, i|
      stripped = line.strip
      if stripped.empty?
        rest_starts_at = i + 1
        break
      end
      if stripped.start_with?("#")  # Heading erreicht
        rest_starts_at = i
        break
      end
      key_value = stripped.match(/\A([A-Za-zÄÖÜäöü\-_]+)\s*:\s*(.+)\z/)
      if key_value
        canonical = canonical_key(key_value[1])
        if canonical
          fm[canonical] = parse_light_value(canonical, key_value[2])
          rest_starts_at = i + 1
          next
        end
      end
      # Linie passt nicht ins Light-Format — Body beginnt hier.
      rest_starts_at = i
      break
    end

    body = lines[rest_starts_at..].to_a.join.sub(/\A# [^\n]*\n+/, "")
    [fm, body]
  end

  def canonical_key(raw)
    needle = raw.downcase.strip
    LIGHT_KEYS.find { |_, aliases| aliases.include?(needle) }&.first
  end

  def parse_light_value(canonical, value)
    case canonical
    when "topics", "tags"
      # "[a, b, c]" oder "a, b, c"
      stripped = value.strip.sub(/\A\[/, "").sub(/\]\z/, "")
      stripped.split(/[,;]\s*/).map(&:strip).reject(&:empty?)
    when "created_at"
      parse_date(value)&.to_s || value.strip
    else
      value.strip
    end
  end

  def parse_date(raw)
    return nil if raw.blank?
    return raw if raw.is_a?(Date) || raw.is_a?(Time)
    text = raw.to_s.strip
    %w[%Y-%m-%d %d.%m.%Y %d/%m/%Y].each do |fmt|
      return Date.strptime(text, fmt)
    rescue ArgumentError
      next
    end
    Date.parse(text) rescue nil
  end

  def derive_title(file, body)
    if (h1 = body.lines.find { |l| l.strip.start_with?("# ") })
      return h1.strip.sub(/\A#\s+/, "")
    end
    file.basename(".md").to_s.tr("-_", " ").split.map(&:capitalize).join(" ")
  end

  # Source-Upsert für Chat/URL-Imports: ist im Frontmatter ein
  # bib_source-Slug gegeben, wird er direkt verlinkt; sonst entweder
  # aus source_url (csl_type webpage / motion_picture) oder aus
  # chat_title (csl_type personal_communication) eine neue Source
  # angelegt und das KI verknüpft.
  YT_URL_RE = %r{\A(?:https?://)?(?:www\.|m\.)?(?:youtube\.com/watch\?|youtu\.be/)}.freeze

  def link_source!(item, fm)
    src =
      if (slug = fm["bib_source"].to_s.strip).present?
        Source.find_by(slug: slug)
      elsif (url = fm["source_url"].to_s.strip).presence
        Source.find_by(url: url) || Source.create!(
          slug:     YT_URL_RE.match?(url) ? "yt-#{url[/(?:v=|youtu\.be\/)([\w-]{6,})/, 1].to_s.downcase}" :
                    URI.parse(url).host.to_s.tr(".", "-").presence || "src-#{SecureRandom.hex(3)}",
          csl_type: YT_URL_RE.match?(url) ? "motion_picture" : "webpage",
          title:    fm["chat_title"].presence || item.title,
          url:      url,
          creator:  @actor
        )
      elsif (chat_title = fm["chat_title"].to_s.strip).presence
        Source.find_by(title: chat_title, csl_type: "personal_communication") ||
          Source.create!(slug: "chat-#{chat_title.parameterize.first(60)}",
                         csl_type: "personal_communication",
                         title:   chat_title,
                         creator: @actor)
      end
    return unless src
    item.update!(bib_source_id: src.id)
    FileProxy.merge_frontmatter!(actor: @actor, knowledge_item: item, bib_source: src.slug)
  rescue ActiveRecord::RecordInvalid, FileProxy::FileNotFound => e
    Rails.logger.warn("WikiImporter#link_source!: #{e.class} #{e.message}")
  end
end
