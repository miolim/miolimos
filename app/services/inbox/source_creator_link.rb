module Inbox
  # #201: Helper für Ingest-Pipelines (YT, WebClip), die Autoren/Channel-
  # Owner als source_creators an einer Source verknüpfen wollen. Legt
  # bei Bedarf ein Person- oder Organization-KI an und verknüpft es per
  # source_creators-Row (role="author").
  #
  # Idempotenz: macht nichts, wenn die Source bereits source_creators hat.
  # Verhindert, dass Re-Imports die vom User händisch gepflegte Liste
  # überschreiben — gleiches Pattern wie in PdfBibImport#sync_creators!.
  class SourceCreatorLink
    # Verknüpft `name` als Organization-KI mit der Source. Liefert die
    # neue/gefundene KI oder nil (z.B. Name leer, KI-Anlage fehlgeschlagen).
    def self.link_organization!(source, name, actor:)
      link!(source, name, item_type: :organization, actor: actor)
    end

    # Verknüpft `name` als Person-KI. Splittet den Namen naiv am letzten
    # Space in given/family. Für Web-Author-Tags mit „Vorname Nachname"-
    # Schema.
    def self.link_person!(source, name, actor:)
      link!(source, name, item_type: :person, actor: actor)
    end

    def self.link!(source, name, item_type:, actor:)
      name = name.to_s.strip
      return nil if name.empty?
      return nil if source.source_creators.exists?

      ki = find_or_create_ki(name, item_type: item_type, actor: actor)
      return nil unless ki
      source.source_creators.create!(knowledge_item_uuid: ki.uuid,
                                     role: "author", position: 0)
      ki
    rescue => e
      Rails.logger.warn("SourceCreatorLink: #{e.class} #{e.message}")
      nil
    end

    def self.find_or_create_ki(name, item_type:, actor:)
      scope = case item_type
              when :organization then KnowledgeItem.organizations
              when :person       then KnowledgeItem.persons
              end
      if (existing = scope.by_title_ci(name).first)
        return existing
      end
      ki = FileProxy.create(actor: actor, title: name,
                            item_type: item_type, content: "")
      if item_type == :person
        given, family = split_person_name(name)
        ki.update!(first_name: given.presence, last_name: family.presence)
      end
      ki
    end

    # „Vorname Nachname" → ["Vorname", "Nachname"].
    # „Vorname Mittel Nachname" → ["Vorname Mittel", "Nachname"].
    # „Mononym" → [nil, "Mononym"].
    def self.split_person_name(name)
      parts = name.to_s.strip.split(/\s+/)
      return [nil, parts.first] if parts.size <= 1
      [parts[0..-2].join(" "), parts.last]
    end
  end
end
