# #512 (Hans, 2026-06-04): Sammelt die in einem KI-Body zitierten Quellen
# fürs Reference-Blade — beide Formen: `[@slug]` (Pandoc-Cite) und
# `[[&key]]` (Quellen-Wikilink, key = Slug oder Titel). Liefert eindeutige
# Source-Records in Fund-Reihenfolge.
class SourceCitations
  def self.for(item)
    body = item.respond_to?(:body) ? item.body.to_s : item.to_s
    return [] if body.blank?

    cite_slugs = body.scan(KnowledgeMarkdown::Citations::CITE_RE).map(&:first)
    amp_keys   = body.scan(/\[\[&\s*([^\]|#^]+?)\s*(?:[|#^][^\]]*)?\]\]/).map { |m| m.first.strip }

    found = []
    found.concat(Source.where(slug: cite_slugs).to_a) if cite_slugs.any?
    amp_keys.each do |k|
      s = Source.find_by(slug: k) || Source.where("LOWER(title) = ?", k.downcase).first
      found << s if s
    end
    found.uniq
  end
end
