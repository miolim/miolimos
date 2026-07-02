# #239 Phase A: Synchronisiert die `relations`-Tabelle mit den
# `[[Target ^anchor_id]]`-Wikilinks im Body eines KI. Wird nach jedem
# Body-Save aufgerufen.
#
# Regeln:
# - Pro `^anchor_id` im Body: ein Relation-Row (eindeutig pro source).
# - Wikilink ohne `^id`: ignoriert (= ungetypte Mention, lebt nur in
#   `knowledge_item_references`).
# - Wikilink mit `^id`, aber Target nicht aufloesbar (kein KI mit
#   passendem Titel/UUID): Relation-Row trotzdem anlegen, target_uuid
#   bleibt ein Pseudo-Wert (= der Target-String). Wenn das Target
#   spaeter angelegt wird, kann `resolve_dangling` den uuid nachziehen.
# - Anchor-Ids, die in der DB existieren aber NICHT mehr im Body
#   vorkommen: `orphaned_at = now`. Werden NICHT geloescht — Provenance
#   bleibt erhalten.
#
# #312 follow-up (Hans, 2026-05-23): `target_block_anchor` mitfuehren.
# Wenn die anchor_id im TARGET-Body als Block-Anker existiert (= der
# User hat einen Copy-Wikilink-Absatzlink gemacht), wird sie hier
# gespeichert. Renderer scrollt damit zum Absatz. Keine Doppelung mehr
# zwischen „bloßer Block-Anker-Verweis" und „typed Relation".
class RelationSync
  WIKILINK_WITH_ANCHOR = /\[\[
    \s*([^\]|#\^]+?)\s*       # 1: target (KI-Title oder UUID), Whitespace getrimmt
    (?:\#[^\]|^]+)?           # optional #heading (ignored)
    \s*\^([0-9a-z]{6})\b      # 2: anchor_id — 6 base36 chars
    (?:\|[^\]]+)?             # optional |display (ignored)
  \]\]/x

  UUID_RE = /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i

  def self.sync(item, body)
    new(item, body).run
  end

  def initialize(item, body)
    @item = item
    @body = body.to_s
    @source_uuid = item.uuid
    @source_type = item.class.name
  end

  def run
    seen_ids = []
    @body.scan(WIKILINK_WITH_ANCHOR) do |target_str, anchor_id|
      target_str = target_str.to_s.strip
      seen_ids << anchor_id
      target_uuid, target_type, target_block_anchor = resolve_target(target_str, anchor_id)

      rel = Relation.find_or_initialize_by(source_uuid: @source_uuid, anchor_id: anchor_id)
      rel.source_type         = @source_type
      rel.target_uuid         = target_uuid
      rel.target_type         = target_type
      rel.target_block_anchor = target_block_anchor
      rel.orphaned_at         = nil
      rel.save!
    end

    # Alles, was VORHER fuer dieses Item da war, aber nicht mehr im
    # Body steht: orphanen (nicht loeschen).
    Relation.for_source(@source_uuid)
            .where(orphaned_at: nil)
            .where.not(anchor_id: seen_ids)
            .update_all(orphaned_at: Time.current)
  end

  private

  # Liefert [target_uuid, target_type, target_block_anchor]. Der dritte
  # Slot ist gesetzt, wenn die `anchor_id` als Block-Anker (`^id` am
  # Zeilenende) im Target-Body existiert — dann wird der Wikilink beim
  # Klick zum Absatz scrollen. Sonst nil = reine Source-/Target-Relation.
  def resolve_target(target_str, anchor_id)
    target = lookup_target(target_str)
    return [target_str, "KnowledgeItem", nil] unless target

    has_block = target.body.to_s.match?(/\^#{Regexp.escape(anchor_id)}(?:\s|$)/)
    [target.uuid, "KnowledgeItem", has_block ? anchor_id : nil]
  end

  def lookup_target(target_str)
    if target_str =~ UUID_RE
      KnowledgeItem.find_by(uuid: target_str.downcase)
    else
      KnowledgeItem.by_title_ci(target_str).first
    end
  end
end
