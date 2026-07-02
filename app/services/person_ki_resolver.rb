# Resolver vom alten "contact slug"-Format auf Person/Org-KIs.
#
# Hintergrund: in YAML-Frontmatter (`contacts:`) und einigen API-Routes
# werden Personen/Orgs noch über kurze Slug-Strings identifiziert
# ("max-mustermann", "anthropic"). Im neuen Modell sind das KIs vom Typ
# `person` oder `organization` ohne eigene Slug-Spalte — dieser Service
# überbrückt das, indem er per parameterize-Match auf existierende KIs
# abbildet und bei Nichttreffer ein neues Person-KI anlegt (Slug mit
# Hyphen → Person, ohne Hyphen → Organization).
class PersonKiResolver
  def self.find_or_create!(slug, actor:)
    text = slug.to_s.strip
    return nil if text.empty?

    if (existing = find(text))
      return existing
    end

    if text.include?("-")
      parts = text.split("-")
      first = parts[0..-2].map(&:capitalize).join(" ")
      last  = parts.last.capitalize
      title = [first, last].reject(&:blank?).join(" ").presence || text.titleize

      item = FileProxy.create(
        actor:     actor,
        title:     title,
        item_type: :person,
        content:   ""
      )
      item.update!(first_name: first.presence, last_name: last.presence)
      item
    else
      title = text.titleize
      FileProxy.create(
        actor:     actor,
        title:     title,
        item_type: :organization,
        content:   ""
      )
    end
  end

  # Lookup ohne Anlage — gibt nil zurück, wenn kein Person/Org-KI mit
  # dem Slug existiert. Vergleich per parameterize gegen die Title-
  # Variante; das ist O(n), wird aber selten aufgerufen (nur beim
  # Reindex-Sync und bei expliziter Slug-Eingabe in der Form).
  def self.find(slug)
    text = slug.to_s.strip
    return nil if text.empty?
    parameterized = text.parameterize
    return nil if parameterized.empty?

    KnowledgeItem.persons_and_orgs.find { |ki| ki.title.parameterize == parameterized }
  end

  # Person-KI anhand E-Mail-Adresse finden oder neu anlegen. Beim Anlegen
  # wird der Display-Name aus dem lokalen Teil der Adresse abgeleitet
  # und ein contact_point mit kind=email angehängt.
  def self.find_or_create_by_email!(email_addr, actor:, display_name: nil)
    addr = email_addr.to_s.strip.downcase
    return nil if addr.empty?

    # #764 (Hans, 2026-06-23): nur LIVE Person/Org-KIs matchen. Der frühere
    # `pick(:knowledge_item_uuid)` + `find_by` nahm den ERSTEN passenden
    # ContactPoint — auch einen VERWAISTEN (eines verworfenen/gelöschten KIs);
    # `find_by` schloss das verworfene KI dann aus (nil) → es wurde trotz
    # vorhandenem Kontakt ein DUPLIKAT angelegt. persons_and_orgs filtert
    # Verworfene → die ContactPoints verworfener KIs werden übersprungen.
    existing = KnowledgeItem.persons_and_orgs
                 .where(uuid: ContactPoint.where(kind: "email")
                                .where("lower(value) = ?", addr)
                                .select(:knowledge_item_uuid))
                 .first
    return existing if existing

    title = display_name.presence || derive_name_from_email(addr)
    parts = title.split(/\s+/)
    first = parts.size > 1 ? parts[0..-2].join(" ") : nil
    last  = parts.last

    item = FileProxy.create(
      actor:     actor,
      title:     title,
      item_type: :person,
      content:   ""
    )
    item.update!(first_name: first, last_name: last)

    # E-Mail über FileProxy.update schreiben — die DB ist Source of Truth
    # (#241 Plan B), die Datei wird als Export aus der DB rekonstruiert;
    # PersonOrgSync mappt die strukturierten Blöcke danach in die DB-Tabellen.
    FileProxy.update(
      actor:          actor,
      knowledge_item: item,
      contact_points: [{ "kind" => "email", "label" => "", "value" => addr }]
    )
    item.reload
  end

  def self.derive_name_from_email(addr)
    local = addr.split("@").first.to_s
    local.split(/[._+-]/).reject(&:blank?).map(&:capitalize).join(" ").presence || local
  end
  private_class_method :derive_name_from_email
end
