require "yaml"

# Schreibt Bestand-Frontmatter mit alten item_type-Strings auf die neuen
# Werte um (vgl. KnowledgeIndexer::ITEM_TYPE_ALIASES). Die DB ist via
# Migration bereits konsolidiert; diese Klasse zieht die Wahrheit auf der
# Platte nach, damit ein Re-Index ohne Alias-Mapping konsistent bliebe.
#
# Idempotent: KIs ohne Frontmatter, ohne Type oder mit bereits aktuellem
# Type werden übersprungen. Mehrfaches Ausführen rewriteet nichts mehr.
class KnowledgeItemTypeBackfill
  Stats = Struct.new(:scanned, :rewritten, :no_frontmatter, :already_current,
                     keyword_init: true)

  ALIAS_MAP = {
    "ai_chat"  => "abstract",
    "web_clip" => "transcript",
    "quote"    => "direct_quote",
    "document" => "transcript"
  }.freeze

  def self.run(actor:, logger: Rails.logger)
    new(actor: actor, logger: logger).run
  end

  def initialize(actor:, logger:)
    @actor  = actor
    @logger = logger
  end

  def run
    scanned = rewritten = no_frontmatter = already_current = 0

    KnowledgeItem.with_discarded.find_each do |item|
      scanned += 1
      case rewrite_one(item)
      when :rewritten       then rewritten += 1
      when :no_frontmatter  then no_frontmatter += 1
      when :already_current then already_current += 1
      end
    end

    Stats.new(scanned: scanned, rewritten: rewritten,
              no_frontmatter: no_frontmatter, already_current: already_current)
  end

  private

  # `read_frontmatter_yaml` schluckt FileNotFound zu "" — das deckt sowohl
  # "Datei fehlt" als auch "MD ohne Frontmatter" als no_frontmatter ab.
  def rewrite_one(item)
    raw_yaml = FileProxy.read_frontmatter_yaml(actor: @actor, knowledge_item: item)
    return :no_frontmatter if raw_yaml.blank?

    fm = YAML.safe_load(raw_yaml, permitted_classes: [Date, Time]) || {}
    old_type = fm["type"].to_s
    return :already_current unless ALIAS_MAP.key?(old_type)

    new_type = ALIAS_MAP[old_type]
    FileProxy.merge_frontmatter!(actor: @actor, knowledge_item: item, type: new_type)
    @logger.info("ItemTypeBackfill: #{item.uuid} #{old_type} → #{new_type}")
    :rewritten
  end
end
