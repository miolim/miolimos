class FileProxy
  # #241 Plan B: Reader liest aus der DB statt von Disk. DB ist Source
  # of Truth; Files sind nur noch Export-Side-Effect (siehe Writer).
  # API bleibt unveraendert: read / read_body / read_frontmatter_yaml.
  module Reader
    extend self

    # Vollstaendiges Markdown rekonstruiert: Frontmatter + H1 + Body.
    # Wird von API und KnowledgeMarkdown-Service genutzt.
    def read(actor:, knowledge_item:)
      AccessGate.authorize!(actor: actor, resource_type: "KnowledgeItem", action: "read")
      fm   = build_frontmatter_hash(knowledge_item)
      body = knowledge_item.body.to_s
      Frontmatter.render(fm: fm, title: knowledge_item.title.to_s, body: body)
    end

    # Body ohne YAML-Frontmatter und ohne fuehrende H1-Zeile.
    # Entspricht 1:1 der `knowledge_items.body`-Spalte.
    def read_body(actor:, knowledge_item:)
      AccessGate.authorize!(actor: actor, resource_type: "KnowledgeItem", action: "read")
      knowledge_item.body.to_s
    end

    # YAML-Frontmatter als String zur Anzeige (Detail-View „Frontmatter
    # einblenden"). Rekonstruiert aus DB-Spalten + Relationen + dem
    # `provenance`-jsonb. Das ist die *abgeleitete* (Export-)Frontmatter,
    # nicht der vom Autor getippte Block — siehe read_authored_frontmatter.
    def read_frontmatter_yaml(actor:, knowledge_item:)
      AccessGate.authorize!(actor: actor, resource_type: "KnowledgeItem", action: "read")
      build_frontmatter_hash(knowledge_item).to_yaml.sub(/^---\n/, "").rstrip
    end

    # #500 (Hans, 2026-06-04): Der vom Autor im Body getippte fuehrende
    # `---`…`---`-Block (freie Schluessel wie typ/ebene/baut_auf/status).
    # Seit dem Frontmatter-Strip wird er nicht mehr als Prosa gerendert —
    # damit er nicht voellig unsichtbar wird, gibt der Frontmatter-Inspektor
    # ihn hier wieder aus. Liefert den rohen YAML-Text zwischen den Fences
    # oder nil, wenn kein fuehrender Block vorhanden ist.
    def read_authored_frontmatter(actor:, knowledge_item:)
      AccessGate.authorize!(actor: actor, resource_type: "KnowledgeItem", action: "read")
      body = knowledge_item.body.to_s
      return nil unless body.lstrip.start_with?("---")
      parts = body.sub(/\A\s*/, "").split(/^---[ \t]*$/, 3)
      return nil unless parts.size >= 3
      inner = parts[1].to_s.strip
      inner.empty? ? nil : inner
    end

    # Öffentlich, damit Writer es nutzen kann.
    def build_frontmatter_hash(ki)
      fm = {
        "id"         => ki.uuid,
        "type"       => ki.item_type.to_s,
        "title"      => ki.title.to_s,
        "created_at" => (ki.file_created_at || ki.created_at)&.iso8601,
        "updated_at" => (ki.file_updated_at || ki.updated_at)&.iso8601
      }
      fm["topics"]   = ki.topics.pluck(:slug)         if ki.respond_to?(:topics) && ki.topics.any?
      fm["contacts"] = ki.mentioned_kis.pluck(:uuid)  if ki.respond_to?(:mentioned_kis) && ki.mentioned_kis.any?
      fm["tags"]     = ki.tags.to_a                   if ki.tags.present?
      fm["aliases"]  = ki.aliases.to_a                if ki.aliases.present?
      fm["first_name"] = ki.first_name                if ki.first_name.present?
      fm["last_name"]  = ki.last_name                 if ki.last_name.present?
      fm["orcid"]      = ki.orcid                      if ki.orcid.present?   # #516
      fm["legal_form"] = ki.legal_form                if ki.legal_form.present?  # #1057
      fm["issuer"]     = true                          if ki.respond_to?(:issuer) && ki.issuer?          # #532
      if ki.parent_org_uuid.present?
        parent = KnowledgeItem.find_by(uuid: ki.parent_org_uuid)
        fm["parent_org"] = parent.title if parent
      end
      fm["creator"]    = ki.creator.name              if ki.creator
      # #460: Supersession ins Export-Frontmatter, damit die Ablösung in
      # der Datei/git-Historie und im „Abgeleitet"-Inspektor sichtbar ist.
      if ki.superseded_by_uuid.present?
        succ = KnowledgeItem.find_by(uuid: ki.superseded_by_uuid)
        fm["superseded_by"] = succ&.title || ki.superseded_by_uuid
      end
      fm["bib_source"] = ki.bib_source.slug           if ki.bib_source
      fm["locator_label"] = ki.locator_label          if ki.locator_label.present?
      fm["locator_value"] = ki.locator_value          if ki.locator_value.present?
      if ki.respond_to?(:provenance) && ki.provenance.present?
        fm["provenance"] = ki.provenance
      end
      fm.compact
    end
  end
end
