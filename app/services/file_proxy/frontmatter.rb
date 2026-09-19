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
              issuer: nil, logo: nil,
              **stammdaten)
      # #1675: Die skalaren Stammdaten (Name, Anrede, Rechtsform …) kommen als
      # **stammdaten und laufen über EINE Liste — KnowledgeItem::Stammdaten.
      unbekannt = stammdaten.keys - KnowledgeItem::Stammdaten::NAMEN
      raise ArgumentError, "unbekannte Frontmatter-Felder: #{unbekannt.inspect}" if unbekannt.any?
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
      # #1075: leere Arrays BEHALTEN (kein .presence) — PersonOrgSync
      # unterscheidet jetzt „Key fehlt" (Bestand nicht anfassen) von
      # „explizit leer" (alles ersetzen/leeren). Mit .presence fiel beides
      # zusammen, und ein nacktes FileProxy.update (z.B. Supersede) räumte
      # einer Person sämtliche Kontaktpunkte/Affiliations/Beziehungen weg.
      fm["affiliations"]   = affiliations   unless affiliations.nil?
      fm["relationships"]  = relationships  unless relationships.nil?
      fm["contact_points"] = contact_points unless contact_points.nil?
      # nil = nicht anfassen; leer oder (bei Katalogfeldern) ungültig räumt
      # den Key ab (fm.compact unten).
      KnowledgeItem::Stammdaten.in_frontmatter!(fm, stammdaten)
      # #1168: Logo als Titel-Referenz auf ein Bild-KI (wie parent_org);
      # "" räumt den Key ab (fm.compact unten).
      fm["logo"]           = logo.presence                                 unless logo.nil?
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
