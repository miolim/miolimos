# Frontmatter-Builder + Markdown-Renderer für FileProxy. Aus
# file_proxy.rb (#127) ausgelagert.
#
# Verantwortlich für:
# - Merge alter Frontmatter mit eingehenden Update-Feldern (build)
# - "render as full file": Frontmatter + H1-Title + Body zu einer
#   `---\n…\n---\n\n# title\n\n…`-Struktur zusammensetzen (render)
class FileProxy
  module Frontmatter
    module_function

    # Mergt eingehende Felder mit dem alten Frontmatter zu einem neuen
    # Hash. `nil`-Werte werden am Schluss aus dem Hash gepolstert (sonst
    # entstünde `key:` ohne Value im YAML).
    def build(old_fm, knowledge_item,
              new_type:,
              topics:, contacts:, tags:, aliases:,
              parent_org:,
              affiliations:, relationships:, contact_points:,
              first_name:, last_name:, orcid: nil,
              legal_form: nil,
              issuer: nil)
      fm = old_fm.merge("updated_at" => Time.current.iso8601)
      fm["topics"]   = Array(topics)   if topics
      fm["contacts"] = Array(contacts) if contacts
      fm["tags"]     = Array(tags)     if tags
      fm["aliases"]  = Array(aliases).reject(&:blank?).presence if aliases
      fm["type"]     = new_type
      # Bestand-Keys aus früheren Datenmodellen aktiv löschen — werden
      # jetzt auf Source-Ebene geführt bzw. existieren gar nicht mehr.
      fm.delete("source")
      fm.delete("source_url")
      fm.delete("chat_title")
      fm["parent_org"]     = parent_org.presence     unless parent_org.nil?
      fm["affiliations"]   = affiliations.presence   unless affiliations.nil?
      fm["relationships"]  = relationships.presence  unless relationships.nil?
      fm["contact_points"] = contact_points.presence unless contact_points.nil?
      fm["first_name"]     = first_name.presence     unless first_name.nil?
      fm["last_name"]      = last_name.presence      unless last_name.nil?
      fm["orcid"]          = orcid.presence          unless orcid.nil?   # #516
      # #1057 (aus immoos #1031): Rechtsform — nur Katalogwerte, alles andere
      # (auch "") räumt den Key ab (fm.compact unten).
      fm["legal_form"]     = (legal_form if LegalForms.valid?(legal_form)) unless legal_form.nil?
      # #761: vat_id-Spalte entfernt — USt-IdNr lebt als Identifier (#544).
      # Alt-Frontmatter-Key aktiv löschen, damit er nicht zurückwandert.
      fm.delete("vat_id")
      # #532 Stammdaten: Aussteller-Flag wird als echter Boolean geführt
      # (false → Key entfernen, hält Frontmatter sauber).
      unless issuer.nil?
        if issuer then fm["issuer"] = true else fm.delete("issuer") end
      end
      fm["id"]           ||= knowledge_item.uuid
      fm.compact
    end

    # Renders Frontmatter + H1-Title + Body als komplette Markdown-Datei.
    def render(fm:, title:, body:)
      "---\n#{fm.to_yaml.sub(/^---\n/, '')}---\n\n# #{title}\n\n#{body}"
    end
  end
end
