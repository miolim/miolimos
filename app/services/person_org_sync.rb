require "set"

# Synchronisiert Affiliations und Relationships aus den strukturierten
# Frontmatter-Blöcken eines Person-/Organization-KI in die DB-Tabellen.
# Source of Truth ist die DB (die Markdown-Datei ist nur noch Export,
# #241 Plan B); das hier aus dem DB-rekonstruierten Frontmatter gelesene
# Frontmatter wird beim Speichern in die relationalen Tabellen gemappt.
#
# Frontmatter-Format:
#   affiliations:
#     - org: <uuid|title>
#       role: Founder
#       from: 2023-01-01
#       to: null
#       primary: true
#   relationships:
#     - to: <uuid|title>
#       kind: Ehepartnerin
#       from: 2010
#       to: null
#
# `from`/`to` akzeptieren Date, ISO-Date-String oder Year-only ("2023").
# Title-Refs werden zur UUID aufgelöst (oder bleiben unverknüpft, wenn
# das Ziel noch nicht existiert).
class PersonOrgSync
  def self.sync(item, frontmatter)
    new(item, frontmatter).sync
  end

  def initialize(item, frontmatter)
    @item = item
    @fm   = frontmatter || {}
  end

  def sync
    sync_affiliations   if @item.item_type == "person"
    sync_relationships  if @item.item_type.in?(%w[person organization])
    sync_contact_points if @item.item_type.in?(%w[person organization])
    # Org-Affiliations werden nicht von der Org-Seite erfasst — sie
    # ergeben sich aus den Person-Affiliations, die per `org:` auf die
    # Org zeigen. Relationships können aber auch auf Org-Seite stehen
    # (z.B. "Tochter-Organisation von …").
  end

  private

  def sync_contact_points
    declared = Array(@fm["contact_points"]).compact
    seen = Set.new

    declared.each_with_index do |entry, i|
      kind  = (entry["kind"]  || entry[:kind]).to_s.strip.downcase
      value = (entry["value"] || entry[:value]).to_s.strip
      next if kind.empty? || value.empty?
      next unless ContactPoint::KINDS.include?(kind)

      label = (entry["label"] || entry[:label]).to_s.strip

      record = @item.contact_points.find_or_initialize_by(
        kind: kind, value: value
      )
      record.assign_attributes(label: label, position: i)
      record.save!
      seen << record.id
    end

    @item.contact_points.where.not(id: seen.to_a).destroy_all
  end

  def sync_affiliations
    declared = Array(@fm["affiliations"]).compact
    seen = Set.new

    declared.each_with_index do |entry, i|
      org_uuid = resolve_uuid(entry["org"] || entry[:org])
      next unless org_uuid

      role     = (entry["role"] || entry[:role]).to_s.strip
      start_at = parse_date(entry["from"] || entry[:from])
      end_at   = parse_date(entry["to"]   || entry[:to])
      primary  = entry["primary"] == true || entry[:primary] == true

      attrs = {
        person_uuid:       @item.uuid,
        organization_uuid: org_uuid,
        role:              role,
        start_at:          start_at,
        end_at:            end_at,
        primary:           primary,
        position:          i
      }

      # Eindeutigkeits-Schlüssel: person + org + role + start_at.
      record = Affiliation.find_or_initialize_by(
        person_uuid:       @item.uuid,
        organization_uuid: org_uuid,
        role:              role,
        start_at:          start_at
      )
      record.assign_attributes(attrs)
      record.save!
      seen << record.id
    end

    @item.affiliations_as_person.where.not(id: seen.to_a).destroy_all
  end

  def sync_relationships
    declared = Array(@fm["relationships"]).compact
    seen = Set.new

    declared.each do |entry|
      to_uuid  = resolve_uuid(entry["to"] || entry[:to])
      next unless to_uuid

      kind     = (entry["kind"] || entry[:kind]).to_s.strip
      next if kind.empty?
      start_at = parse_date(entry["from"]  || entry[:from] || entry["since"] || entry[:since])
      end_at   = parse_date(entry["to_at"] || entry[:to_at] || entry["until"]|| entry[:until])

      record = Relationship.find_or_initialize_by(
        from_uuid: @item.uuid,
        to_uuid:   to_uuid,
        kind:      kind,
        start_at:  start_at
      )
      record.assign_attributes(end_at: end_at)
      record.save!
      seen << record.id
    end

    @item.outgoing_relationships.where.not(id: seen.to_a).destroy_all
  end

  UUID_RE = /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i

  def resolve_uuid(ref)
    return nil if ref.blank?
    s = ref.to_s.strip
    return s.downcase if s =~ UUID_RE
    KnowledgeItem.by_title_ci(s).first&.uuid
  end

  def parse_date(value)
    return nil if value.blank?
    return value if value.is_a?(Date)
    return value.to_date if value.is_a?(Time) || value.is_a?(DateTime)
    s = value.to_s.strip
    return nil if s.empty?
    # Year-only: "2023" → 2023-01-01
    return Date.new(s.to_i, 1, 1) if s =~ /\A\d{4}\z/
    Date.parse(s) rescue nil
  end
end
