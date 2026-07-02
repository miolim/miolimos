require "yaml"

# Parser für YAML-Frontmatter in Markdown-Dateien.
#
# Vorher fünfmal in der Codebase als kopierte Schleife implementiert
# (FileProxy x2, KnowledgeIndexer, WikiImporter, _detail.html.erb).
# Liefert immer ein 2-Tupel [hash, body] — ohne Frontmatter:
# [{}, content].
#
#   MarkdownFrontmatter.parse("---\nkey: value\n---\n\nbody")
#   # => [{"key" => "value"}, "body"]
#
# `strip_h1: true` (Default) entfernt zusätzlich eine führende `# Title`-
# Zeile aus dem Body — das machen alle Aufrufer außer append_session.
class MarkdownFrontmatter
  def self.parse(content, strip_h1: true)
    return [{}, content.to_s] unless content.to_s.start_with?("---")
    parts = content.split(/^---\s*$/, 3)
    return [{}, content] unless parts.size >= 3

    data = YAML.safe_load(parts[1], permitted_classes: [Date, Time], aliases: false) || {}
    body = parts[2].to_s.sub(/\A\n/, "")
    body = body.sub(/\A# [^\n]*\n+/, "") if strip_h1
    [data.is_a?(Hash) ? data : {}, body]
  end
end
