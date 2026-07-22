# #761 (Hans, 2026-06-23): Übernimmt aus einer Quelle extrahierte
# Kontaktdaten (ContactExtractor) in die LEEREN Felder eines Person-/
# Organisations-KI — bestehende Werte werden nie überschrieben. Geteilt
# vom Person-Quick-Add (KnowledgeItemsController#create, enrich_url-Param)
# und dem Globus-Icon (#complete_from_url).
#
# #801 P2: aus KnowledgeItemsController extrahiert (war dort ~80 Zeilen
# private Domänenlogik und nur über Render-Tests erreichbar).
class ContactEnrichment
  CP_LABELS = { "email" => "E-Mail", "phone" => "Telefon", "fax" => "Fax", "url" => "Web" }.freeze

  # Komfort: URL extrahieren + anwenden. Wirft ContactExtractor::Error weiter.
  def self.from_url(item:, actor:, url:)
    new(item: item, actor: actor).apply(ContactExtractor.call(url), source_url: url)
  end

  def initialize(item:, actor:)
    @item  = item
    @actor = actor
  end

  # Übernimmt extrahierte Felder in leere Stellen; gibt die Liste der
  # tatsächlich ergänzten Feld-Labels (für die Toast-Meldung) zurück.
  def apply(data, source_url: nil)
    added = []
    data  = data.dup
    # #761-Folge (Hans): nennt das Impressum die Webseite nicht wörtlich,
    # die Domain der Quell-URL als Web-Kontaktpunkt verwenden.
    if data[:url].to_s.strip.blank? && (site = derive_site_url(source_url)).present?
      data[:url] = site
    end

    existing = @item.contact_points.to_a
    merged   = existing.map { |c| { "kind" => c.kind, "value" => c.value, "label" => c.label.to_s } }
    %w[email phone fax url].each do |kind|
      val = data[kind.to_sym].to_s.strip
      next if val.blank?
      next if existing.any? { |c| c.kind == kind && c.value.to_s.strip.casecmp?(val) }
      merged << { "kind" => kind, "value" => val }
      added  << CP_LABELS[kind]
    end
    org = (@item.item_type == "person" && @item.parent_org_uuid.blank?) ? data[:organization].to_s.strip.presence : nil
    if merged.size != existing.size || org
      FileProxy.update(actor: @actor, knowledge_item: @item,
                       contact_points: merged, parent_org: org)
      added << I18n.t("knowledge.detail.complete_org_field") if org
    end

    # #761-Folge (Hans): USt-IdNr + Handelsregister gehören als IDENTIFIER in
    # den IDs-Bereich (#544) — nicht in die deprecated vat_id-Spalte, die in
    # der Detail-Ansicht gar nicht angezeigt wird.
    added << "USt-IdNr" if add_identifier_if_absent("USt-IdNr", data[:vat_id])
    # #1094 (Hans, 2026-07-22): Gericht und Nummer werden getrennt abgelegt —
    # eine HRB-Nummer ist nur zusammen mit ihrem Gericht eindeutig, und beide
    # Angaben werden einzeln gebraucht (Briefkopf, Rechnung, Suche). Nur wenn
    # sich aus dem Impressum keine Nummer herauslesen lässt, bleibt der Rohtext
    # wie bisher als ein Feld „Handelsregister" stehen.
    court, number = self.class.split_register(data[:register])
    if number
      added << "Registergericht"        if add_identifier_if_absent("Registergericht", court)
      added << "Handelsregisternummer"  if add_identifier_if_absent("Handelsregisternummer", number)
    else
      added << "Handelsregister" if add_identifier_if_absent("Handelsregister", data[:register])
    end

    if (addr = data[:address]).is_a?(Hash) && @item.postal_addresses.empty?
      rec = @item.postal_addresses.new(
        line1: addr[:line1], line2: addr[:line2], postal_code: addr[:postal_code],
        city:  addr[:city],  country: addr[:country], position: 0)
      added << I18n.t("knowledge.detail.complete_address_field") if rec.lines.any? && rec.save
    end
    added.uniq
  end

  # #1094: Zerlegt eine Handelsregister-Angabe („Amtsgericht Lübeck HRB 12345",
  # „HRB 12345 B, Amtsgericht Charlottenburg", „Registergericht: AG München,
  # HRB 123456") in [Gericht, Nummer]. Ohne erkennbare Registernummer kommt
  # [nil, nil] zurück — der Aufrufer legt den Rohtext dann ungeteilt ab, damit
  # eine ungewohnte Schreibweise nichts verschluckt.
  REGISTER_NUMBER = /\b(HRA|HRB|GnR|PR|VR)\b\s*\.?\s*(\d+)\s*([A-Za-z]\b)?/i
  # Wörter, die nur die Angabe einleiten und nicht zum Gerichtsnamen gehören.
  REGISTER_NOISE  = /\b(Registergericht|Register|Handelsregister|Genossenschaftsregister|Vereinsregister|Partnerschaftsregister|eingetragen(e[rs]?)?|beim|im|am|Nummer|Nr\.?)\b/i

  def self.split_register(raw)
    s = raw.to_s.strip
    return [nil, nil] if s.blank?
    m = s.match(REGISTER_NUMBER)
    return [nil, nil] unless m
    number = [m[1].upcase, m[2], m[3]&.upcase].compact.join(" ").squish
    court  = s.sub(m[0], " ").gsub(REGISTER_NOISE, " ").gsub(/[,;·|()\/]+/, " ").squish
    court  = court.sub(/\A[-–:]+\s*/, "").sub(/[-–:,;]+\z/, "").strip
    # Führende Artikel/Präpositionen und angehängte Bindewörter gehören zum
    # Satz („eingetragen im … des Amtsgerichts Köln unter HRA 987"), nicht
    # zum Gerichtsnamen.
    court  = court.sub(/\A(des|der|dem|den|bei|beim|von|vom)\s+/i, "")
                  .sub(/\s+(unter|mit)\z/i, "").strip
    [court.presence, number]
  end

  private

  # Legt einen Identifier (label/value) an, wenn weder dieses Label noch
  # dieser Wert schon vorhanden ist. Gibt true zurück, wenn angelegt.
  def add_identifier_if_absent(label, value)
    v = value.to_s.strip
    return false if v.blank?
    return false if @item.identifiers.any? { |i|
      i.label.to_s.casecmp?(label) || i.value.to_s.strip.casecmp?(v) }
    @item.identifiers.create!(label: label, value: v, position: @item.identifiers.count)
    true
  end

  # Ableitung der Webseiten-URL (Schema + Host) aus einer Quell-URL.
  def derive_site_url(source_url)
    return nil if source_url.to_s.strip.empty?
    uri = URI.parse(source_url.strip)
    uri.host.present? ? "#{uri.scheme}://#{uri.host}" : nil
  rescue URI::InvalidURIError
    nil
  end
end
