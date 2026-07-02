require "digest"
require "pathname"
require "yaml"

class KnowledgeIndexer
  KNOWLEDGE_ROOT    = "knowledge"
  ITEM_TYPE_BY_DIR  = {
    "notes"         => "note",
    "abstracts"     => "abstract",
    "transcripts"   => "transcript",
    "quotes"        => "direct_quote",
    "people"        => "person",
    "organizations" => "organization",
    "docs"          => "doc",
    # Bestand: alte Subdirs werden auf neue Item-Types gemappt, damit
    # Bestand-Files ohne Move im neuen Schema laufen.
    "ai-chats"      => "abstract",
    "research"      => "transcript",
    "documents"     => "transcript"
  }.freeze

  # Frontmatter-Aliase: Bestand-Files schreiben weiterhin alte type-
  # Strings; der Indexer mappt sie auf die neuen Werte. Backfill-Skript
  # schreibt Frontmatter beim ersten Lauf um — bis dahin dieser Schutz.
  ITEM_TYPE_ALIASES = {
    "ai_chat"  => "abstract",
    "web_clip" => "transcript",
    "quote"    => "direct_quote",
    "document" => "transcript"
  }.freeze

  Stats = Struct.new(:scanned, :created, :updated, :unchanged, :orphaned, :references, keyword_init: true)

  def self.run
    new.run
  end

  def run
    stats = Stats.new(scanned: 0, created: 0, updated: 0, unchanged: 0, orphaned: 0, references: 0)
    return stats unless knowledge_root.exist?

    seen_uuids = Set.new

    markdown_files.each do |md_path|
      stats.scanned += 1
      result = index_markdown(md_path)
      next unless result

      seen_uuids << result[:uuid]
      stats[result[:outcome]] += 1 if stats.respond_to?(result[:outcome])
    end

    sidecar_files.each do |(binary_path, sidecar_path)|
      stats.scanned += 1
      result = index_sidecar(binary_path, sidecar_path)
      next unless result

      seen_uuids << result[:uuid]
      stats[result[:outcome]] += 1 if stats.respond_to?(result[:outcome])
    end

    orphan_count = mark_orphans(seen_uuids)
    stats.orphaned = orphan_count

    ref_count = rebuild_references
    stats.references = ref_count

    stats
  end

  private

  def knowledge_root
    FileProxy::BASE_PATH.join(KNOWLEDGE_ROOT)
  end

  def markdown_files
    Pathname.glob(knowledge_root.join("**", "*.md"))
  end

  def sidecar_files
    Pathname.glob(knowledge_root.join("**", "*.meta.yml")).filter_map do |sidecar|
      binary = sidecar.sub_ext("").sub_ext("")
      # sidecar: foo.pdf.meta.yml → first sub_ext drops .yml → foo.pdf.meta → second drops .meta → foo.pdf
      next nil unless binary.exist?
      [binary, sidecar]
    end
  end

  def index_markdown(md_path)
    content = md_path.read
    frontmatter, body = parse_frontmatter(content)
    return nil unless frontmatter.is_a?(Hash)

    uuid = frontmatter["id"] || frontmatter[:id]
    return nil if uuid.blank?

    title = (frontmatter["title"] || derive_title_from_filename(md_path, body)).to_s.strip
    return nil if title.blank?

    relative_path = md_path.relative_path_from(FileProxy::BASE_PATH).to_s
    hash          = Digest::SHA256.hexdigest(content)

    item = KnowledgeItem.find_by(uuid: uuid)
    outcome =
      if item.nil?
        item = KnowledgeItem.new(uuid: uuid)
        :created
      elsif item.content_hash == hash
        :unchanged
      else
        :updated
      end

    apply_attributes(item, frontmatter: frontmatter, title: title, relative_path: relative_path, hash: hash, default_type: infer_type(md_path))
    item.body = strip_h1(body)
    item.save!

    if outcome != :unchanged
      sync_topics(item, frontmatter["topics"] || [])
      sync_mentions(item, frontmatter["contacts"] || [])
      References.insert_from_body(item, body)
      PersonOrgSync.sync(item, frontmatter) if item.item_type.in?(%w[person organization])
    end

    { uuid: uuid, outcome: outcome }
  end

  def index_sidecar(binary_path, sidecar_path)
    frontmatter = YAML.safe_load(sidecar_path.read, permitted_classes: [Date, Time], aliases: false)
    return nil unless frontmatter.is_a?(Hash)

    uuid = frontmatter["id"] || frontmatter[:id]
    return nil if uuid.blank?

    title = (frontmatter["title"] || binary_path.basename.to_s).to_s.strip

    relative_path = binary_path.relative_path_from(FileProxy::BASE_PATH).to_s
    hash          = Digest::SHA256.file(binary_path).hexdigest

    item = KnowledgeItem.find_by(uuid: uuid)
    outcome =
      if item.nil?
        item = KnowledgeItem.new(uuid: uuid)
        :created
      elsif item.content_hash == hash
        :unchanged
      else
        :updated
      end

    apply_attributes(item, frontmatter: frontmatter, title: title, relative_path: relative_path, hash: hash, default_type: "document")
    item.save!

    if outcome != :unchanged
      sync_topics(item, frontmatter["topics"] || [])
      sync_mentions(item, frontmatter["contacts"] || [])
    end

    { uuid: uuid, outcome: outcome }
  end

  def apply_attributes(item, frontmatter:, title:, relative_path:, hash:, default_type:)
    item.title           = title
    raw_type             = (frontmatter["type"] || default_type).to_s
    item.item_type       = ITEM_TYPE_ALIASES[raw_type] || raw_type
    item.aliases         = Array(frontmatter["aliases"]).compact.map(&:to_s).reject(&:blank?)
    item.tags            = Array(frontmatter["tags"]).compact.map(&:to_s).reject(&:blank?)
    item.first_name      = frontmatter["first_name"]
    item.last_name       = frontmatter["last_name"]
    item.parent_org_uuid = References.resolve_parent_org_uuid(frontmatter["parent_org"])
    item.file_path       = relative_path
    item.content_hash    = hash
    item.file_created_at = parse_time(frontmatter["created_at"]) || Time.current
    item.file_updated_at = parse_time(frontmatter["updated_at"]) || Time.current
    item.indexed_at      = Time.current
    # Creator aus Frontmatter nachziehen, wenn DB ihn noch nicht kennt.
    # Lookup case-insensitiv per Name; was nicht matcht, bleibt nil.
    if item.creator_id.nil? && (creator_name = frontmatter["creator"]).present?
      item.creator = lookup_actor_by_name(creator_name)
    end
    # bib_source-Slug → Source-Lookup, ebenfalls nur wenn DB nichts hat.
    # So überschreibt ein FM-Eintrag eine bestehende Verknüpfung nicht.
    if item.bib_source_id.nil? && (slug = frontmatter["bib_source"]).present?
      if (src = Source.find_by(slug: slug.to_s.strip))
        item.bib_source_id = src.id
      end
    end
  end

  def lookup_actor_by_name(name)
    Actor.where("LOWER(name) = ?", name.to_s.strip.downcase).first
  end

  def parse_frontmatter(content)
    # Indexer braucht den Body MIT "# Title" für derive_title_from_filename
    # (das schaut nach einer h1-Zeile als Fallback-Title).
    MarkdownFrontmatter.parse(content, strip_h1: false)
  end

  # Für die Volltextsuche speichern wir den Body OHNE führenden H1 in
  # knowledge_items.body (Trigger pflegt search_vector).
  def strip_h1(body)
    body.to_s.sub(/\A# [^\n]*\n+/, "")
  end

  def parse_time(value)
    return nil if value.blank?
    return value if value.is_a?(Time) || value.is_a?(DateTime)
    return value.to_time if value.is_a?(Date)
    Time.iso8601(value.to_s)
  rescue ArgumentError
    nil
  end

  def derive_title_from_filename(md_path, body)
    heading = body.to_s.lines.find { |line| line.start_with?("# ") }
    return heading.sub(/^#\s+/, "").strip if heading
    md_path.basename(".md").to_s.sub(/\A\d{4}-\d{2}-\d{2}-/, "").gsub("-", " ").split.map(&:capitalize).join(" ")
  end

  def infer_type(md_path)
    rel = md_path.relative_path_from(knowledge_root).to_s
    subdir = rel.split(File::SEPARATOR).first
    ITEM_TYPE_BY_DIR[subdir] || "note"
  end

  def sync_topics(item, slugs)
    normalized = Array(slugs).compact.map(&:to_s).reject(&:blank?)
    return item.knowledge_item_topics.destroy_all if normalized.empty?

    topic_ids = normalized.map { |slug| find_or_create_topic(slug).id }

    existing = item.knowledge_item_topics.pluck(:topic_id)
    (topic_ids - existing).each do |tid|
      item.knowledge_item_topics.create!(topic_id: tid)
    end
    item.knowledge_item_topics.where.not(topic_id: topic_ids).destroy_all
  end

  # Frontmatter-`contacts:`-Liste (Slug-Strings) auf KI-Mentions abbilden.
  # Slugs werden auf existierende Person/Org-KIs gemappt; fehlt eines,
  # wird ein neues angelegt.
  def sync_mentions(item, slugs)
    normalized = Array(slugs).compact.map(&:to_s).reject(&:blank?)
    return item.knowledge_item_mentions.destroy_all if normalized.empty?

    target_uuids = normalized.filter_map { |slug| PersonKiResolver.find_or_create!(slug, actor: indexer_creator)&.uuid }
    MentionReconciler.reconcile!(item.knowledge_item_mentions, target_uuids,
                                  exclude_self_uuid: item.uuid)
  end

  def find_or_create_topic(slug)
    Topic.find_or_create_from_slug!(slug, creator: indexer_creator)
  end

  def indexer_creator
    @indexer_creator ||= HumanActor.order(:id).first ||
      raise("KnowledgeIndexer needs at least one HumanActor to attribute auto-created topics to")
  end

  # Public entries fuer FileProxy::Writer — delegieren an das
  # References-Modul (E.9). Werden hier als One-Liner exponiert, damit
  # die externe API stabil bleibt.
  def self.resolve_parent_org_uuid(value)       = References.resolve_parent_org_uuid(value)
  def self.index_body_references_for(item, body) = References.index_body_references_for(item, body)
  def self.resolve_dangling_references_to(t, u)  = References.resolve_dangling_references_to(t, u)

  def rebuild_references
    References.rebuild_all
  end

  # KIs aufräumen, deren Backing-Datei (oder Sidecar) nicht mehr existiert.
  # Wichtig: Person/Org-KIs, die *während* dieses Indexer-Laufs durch
  # `sync_mentions` per PersonKiResolver auto-angelegt wurden, sind nicht
  # in `seen_uuids` (die Dateien wurden nach `markdown_files` enumerated
  # erzeugt). Wir prüfen den Disk-Status, damit wir sie nicht direkt
  # wieder löschen.
  def mark_orphans(seen_uuids)
    candidates = KnowledgeItem.where.not(uuid: seen_uuids.to_a)
    orphans = candidates.select do |ki|
      rel = ki.file_path.to_s
      next true if rel.empty?
      full = FileProxy::BASE_PATH.join(rel)
      sidecar = Pathname.new("#{full}.meta.yml")
      !full.exist? && !sidecar.exist?
    end
    orphans.each(&:destroy)
    orphans.size
  end
end
