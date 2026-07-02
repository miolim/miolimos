# #516 (Hans, 2026-06-05): Autoren an eine Quelle hängen — Eingangs-Teil
# des Personen-Modells. Für einen Autorennamen wird eine (provisorische)
# Personen-KI find-or-create und als author verknüpft. Die Verknüpfung ist
# standardmäßig `provisional` (Namens-Stub, noch nicht identifiziert). So ist
# die Quelle sofort zitierfähig (Autor-Nachname → Citekey), die echte
# Identifizierung passiert später ([[Verfahren: Entitäts-Recherche]]).
class Authorship
  STUB_TAG = "namens-stub".freeze

  def self.attach_by_name(source:, name:, actor:, role: "author")
    name = name.to_s.strip
    return nil if name.blank?

    person = find_or_create_person(name, actor)
    sc = SourceCreator.find_or_initialize_by(source: source,
                                             knowledge_item_uuid: person.uuid,
                                             role: role)
    sc.position ||= (source.source_creators.maximum(:position) || -1) + 1
    sc.identification ||= "provisional"
    sc.save!
    sc
  end

  # Bestehende Person nach Titel/Alias (CI) finden, sonst einen
  # provisorischen Namens-Stub anlegen (Nachname/Vorname aus dem Namen).
  def self.find_or_create_person(name, actor)
    scope    = KnowledgeItem.where(item_type: %w[person organization])
    existing = scope.by_title_ci(name).first ||
               scope.where("EXISTS (SELECT 1 FROM unnest(aliases) a WHERE LOWER(a) = ?)", name.downcase).first
    return existing if existing

    last, first = split_name(name)
    ki = FileProxy.create(
      actor:     actor,
      title:     name,
      item_type: "person",
      content:   "Provisorische Personen-KI (Namens-Stub), angelegt beim Quellen-Import. " \
                 "Noch nicht recherchiert/identifiziert — siehe [[Verfahren: Entitäts-Recherche]].",
      tags:      [STUB_TAG]
    )
    ki.update!(last_name: last, first_name: first.presence) if last.present?
    ki
  end

  # #516: Zwei Personen-KIs zusammenführen (Merge). Quellen-Autorschaft der
  # Dublette auf die Zielperson umhängen (Dubletten je Source+Rolle vermeiden),
  # den Namen der Dublette als Alias an die Zielperson, und die Dublette als
  # abgelöst markieren (Supersession). Quellen-Verknüpfungen sind der Kern;
  # tiefere Repointings (Relations/Mentions) sind eine spätere Erweiterung.
  def self.merge_persons(duplicate, target, actor:)
    raise ArgumentError, "Eine Person kann nicht in sich selbst gemergt werden" if duplicate.uuid == target.uuid

    SourceCreator.where(knowledge_item_uuid: duplicate.uuid).find_each do |sc|
      if SourceCreator.where(source_id: sc.source_id, knowledge_item_uuid: target.uuid, role: sc.role).exists?
        sc.destroy
      else
        sc.update!(knowledge_item_uuid: target.uuid)
      end
    end

    target.update!(aliases: (Array(target.aliases) + [duplicate.title]).map { |a| a.to_s.strip }.uniq.reject(&:blank?))
    duplicate.mark_superseded_by!(target, actor: actor)
    target
  end

  # #516 (Hans, 2026-06-05): Best-Effort-Split Vorname/Nachname. Der volle
  # Name bleibt die kanonische Identität (`title`); first/last sind eine
  # ableitbare Bequemlichkeit (Citekey-Nachname, „Nachname, Vorname"-Anzeige,
  # Sortierung) — und jederzeit überschreibbar (Felder/API). Behandelt die
  # häufigen westeuropäischen Fälle: Komma-Form, mehrere Vornamen,
  # Adels-/Präpositions-Partikel (von der Heide, van Beethoven). Keine
  # Anstrengung für perfekte Namensparser über alle Kulturen — das macht
  # bei Bedarf die Entitäts-Recherche.
  PARTICLES = %w[von vom van de der den del della di da das dos zu zum le la
                 ten ter du af av].freeze

  def self.split_name(name)
    name = name.to_s.strip
    if name.include?(",")
      l, f = name.split(",", 2).map(&:strip)
      return [l, f.presence]
    end
    parts = name.split
    return [parts.first, nil] if parts.size <= 1
    # Nachname ab dem ersten Partikel (nicht erstes/letztes Wort) bis zum
    # Ende; sonst nur das letzte Wort.
    idx = (1...(parts.size - 1)).find { |i| PARTICLES.include?(parts[i].downcase) }
    if idx
      [parts[idx..].join(" "), parts[0...idx].join(" ").presence]
    else
      [parts.last, parts[0..-2].join(" ").presence]
    end
  end
end
