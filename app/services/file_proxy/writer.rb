class FileProxy
  # Schreib-Operationen: neue KIs anlegen (Markdown oder Binaer), updaten,
  # Append-Session. Inklusive der Helfer fuer Title-Rewrite, Path-Move
  # und Assoziations-Sync.
  module Writer
    extend self

    def create(actor:, title:, item_type:, content:,
               topics: [], contacts: [], references: [], tags: [],
               aliases: [], enforce_title_uniqueness: false)
      AccessGate.authorize!(actor: actor, resource_type: "KnowledgeItem", action: "create")

      # #202: Title-Uniqueness optional vorab pruefen — nur fuer user-
      # facing-Anlage (das New-Card-Form). Interne Aufrufe wie comment_at
      # erzeugen bewusst gleichlautende Titel und brauchen den Check nicht.
      title_check = title.to_s.strip
      if enforce_title_uniqueness && title_check.present? &&
         KnowledgeItem.where(deleted_at: nil)
                      .where("lower(title) = ?", title_check.downcase)
                      .exists?
        dummy = KnowledgeItem.new(title: title_check, item_type: item_type)
        dummy.errors.add(:title, :taken, message: "ist bereits vergeben")
        raise ActiveRecord::RecordInvalid.new(dummy)
      end

      uuid          = SecureRandom.uuid
      slug          = title.parameterize.presence || "note"
      subdir        = Paths.type_to_subdir(item_type)
      relative_path = Paths.unique_relative_path(subdir: subdir, slug: slug)

      frontmatter = {
        "id"         => uuid,
        "type"       => item_type.to_s,
        "aliases"    => Array(aliases).reject(&:blank?).presence,
        "creator"    => actor.name,
        "created_at" => Time.current.iso8601,
        "updated_at" => Time.current.iso8601,
        "topics"     => topics,
        "contacts"   => contacts,
        "tags"       => tags
      }.compact

      body = content.to_s
      body = "#{body}\n\n#{references.map { |ref| "[[#{ref}]]" }.join(' ')}" if references.any?

      full_content = Frontmatter.render(fm: frontmatter, title: title, body: body)

      full_path = BASE_PATH.join(relative_path)
      FileUtils.mkdir_p(File.dirname(full_path))
      File.write(full_path, full_content)

      GitRepo.commit(actor: actor, file_path: relative_path, message: "Add #{item_type}: #{title}")

      item = KnowledgeItem.create!(
        uuid: uuid,
        title: title,
        item_type: item_type,
        aliases: Array(aliases).reject(&:blank?),
        tags:    Array(tags).reject(&:blank?),
        body:    body.to_s,
        file_path: relative_path,
        content_hash: Digest::SHA256.hexdigest(full_content),
        file_created_at: Time.current,
        file_updated_at: Time.current,
        indexed_at: Time.current,
        creator: actor.is_a?(Actor) ? actor : nil
      )

      link_slugs(item, actor: actor, topic_slugs: topics, contact_slugs: contacts)
      KnowledgeIndexer.index_body_references_for(item, body) if body.present?
      KnowledgeIndexer.resolve_dangling_references_to(item.title, item.uuid)
      RelationSync.sync(item, body) if body.present?
      PersonOrgSync.sync(item, frontmatter) if item.item_type.in?(%w[person organization])
      # #384 Phase 2 (Hans, 2026-05-27): @-Mentions auf App-Nutzer.
      # #587: frisch erwaehnte Agenten poken (nur Body-Mentions normaler
      # KIs — Replies pokt der Replies-Controller).
      if body.present?
        new_mention_ids = KnowledgeMarkdown::ActorMentions.sync_for(item, body)
        BuilderInboxPoke.poke_body_mentions(item, new_mention_ids, except: actor)
      end
      KnowledgeMarkdown::Anchors.sync_for(item, body)        if body.present?
      item
    end

    # Speichert eine hochgeladene Binaer-Datei (z.B. PDF) plus Sidecar
    # `<file>.meta.yml` mit Frontmatter. Indexer-konformes Layout,
    # dasselbe Pattern wie eine extern abgelegte Datei. uploaded_io ist
    # ein ActionDispatch::Http::UploadedFile (oder File-IO).
    def create_with_file(actor:, title:, uploaded_io:,
                         item_type: :transcript,
                         topics: [], contacts: [], tags: [])
      AccessGate.authorize!(actor: actor, resource_type: "KnowledgeItem", action: "create")

      uuid          = SecureRandom.uuid
      slug          = title.parameterize.presence || "document"
      subdir        = Paths.type_to_subdir(item_type)
      ext           = File.extname(uploaded_io.respond_to?(:original_filename) ? uploaded_io.original_filename : uploaded_io.path).downcase
      ext           = ".bin" if ext.empty?
      relative_path = Paths.unique_relative_path(subdir: subdir, slug: slug, extension: ext)

      full_path = BASE_PATH.join(relative_path)
      FileUtils.mkdir_p(File.dirname(full_path))
      File.open(full_path, "wb") do |f|
        uploaded_io.rewind if uploaded_io.respond_to?(:rewind)
        IO.copy_stream(uploaded_io, f)
      end

      frontmatter = {
        "id"         => uuid,
        "title"      => title,
        "type"       => item_type.to_s,
        "creator"    => actor.name,
        "created_at" => Time.current.iso8601,
        "updated_at" => Time.current.iso8601,
        "topics"     => topics,
        "contacts"   => contacts,
        "tags"       => tags
      }.compact
      sidecar_path = "#{relative_path}.meta.yml"
      File.write(BASE_PATH.join(sidecar_path), frontmatter.to_yaml)

      GitRepo.commit(actor: actor, file_path: [relative_path, sidecar_path],
                     message: "Add #{item_type}: #{title}")

      item = KnowledgeItem.create!(
        uuid: uuid,
        title: title,
        item_type: item_type,
        file_path: relative_path,
        content_hash: Digest::SHA256.file(full_path).hexdigest,
        file_created_at: Time.current,
        file_updated_at: Time.current,
        indexed_at: Time.current,
        creator: actor.is_a?(Actor) ? actor : nil
      )

      link_slugs(item, actor: actor, topic_slugs: topics, contact_slugs: contacts)
      item
    end

    # Ueberschreibt Body + Frontmatter einer bestehenden Datei. UUID
    # bleibt stabil (externe Wikilinks-Referenzen ueberleben). Bei
    # Title-Wechsel wird die Datei umbenannt UND in allen Backlink-
    # Quellen werden die `[[Alter Titel]]`-Wikilinks zu `[[Neuer
    # Titel]]` rewritten. Bei item_type-Wechsel wird die Datei in den
    # passenden Subdir verschoben.
    def update(actor:, knowledge_item:, title: nil, content: nil,
               topics: nil, contacts: nil, tags: nil, aliases: nil,
               item_type: nil,
               parent_org: nil, affiliations: nil, relationships: nil,
               contact_points: nil,
               first_name: nil, last_name: nil, orcid: nil,
               issuer: nil)
      AccessGate.authorize!(actor: actor, resource_type: "KnowledgeItem", action: "update")

      # #241 Plan B: existing body kommt aus DB, Frontmatter wird aus
      # DB-Spalten rekonstruiert. Datei dient nur noch als Export-
      # Target; ihr Inhalt ist hier nicht mehr Quelle.
      full_path       = BASE_PATH.join(knowledge_item.file_path)
      existing_body   = knowledge_item.body.to_s
      old_frontmatter = Reader.build_frontmatter_hash(knowledge_item)
      old_title       = knowledge_item.title
      new_title     = title.presence || old_title
      new_type      = (item_type.presence || knowledge_item.item_type).to_s
      title_changed = title.present? && title != old_title
      type_changed  = item_type.present? && new_type != knowledge_item.item_type
      new_body      = content.nil? ? existing_body.to_s : content.to_s

      fm = Frontmatter.build(
        old_frontmatter, knowledge_item,
        new_type:       new_type,
        topics:         topics,
        contacts:       contacts,
        tags:           tags,
        aliases:        aliases,
        parent_org:     parent_org,
        affiliations:   affiliations,
        relationships:  relationships,
        contact_points: contact_points,
        first_name:     first_name,
        last_name:      last_name,
        orcid:          orcid,
        issuer:         issuer
      )

      # #650 (Hans, 2026-06-12): Binär-Datei-KIs (Bild/PDF — alles ohne
      # .md-Endung) dürfen beim Update NIEMALS mit Frontmatter+Body
      # überschrieben werden. Eine Umbenennung hat so eine .jpg in eine
      # .md-Textdatei verwandelt und das Bild zerstört. Binär-Pfad:
      # Datei verschieben (Endung bleibt), Sidecar-Frontmatter pflegen.
      binary_asset = !knowledge_item.file_path.to_s.match?(/\.(md|markdown)\z/i)
      if binary_asset
        new_relative_path =
          if title_changed || type_changed
            Paths.unique_relative_path(
              subdir:    Paths.type_to_subdir(new_type),
              slug:      (new_title.parameterize.presence || "datei"),
              extension: File.extname(knowledge_item.file_path).downcase
            )
          else
            knowledge_item.file_path
          end
        move_binary_asset!(actor: actor, knowledge_item: knowledge_item, fm: fm,
                           new_relative_path: new_relative_path,
                           old_title: old_title, new_title: new_title)
        knowledge_item.update!(
          title:           new_title,
          item_type:       new_type,
          aliases:         Array(fm["aliases"]),
          tags:            Array(fm["tags"]),
          file_path:       new_relative_path,
          content_hash:    Digest::SHA256.file(BASE_PATH.join(new_relative_path)).hexdigest,
          file_updated_at: Time.current,
          indexed_at:      Time.current
        )
        sync_associations(actor: actor, item: knowledge_item, fm: fm,
                          topics: topics, contacts: contacts, body: existing_body)
        rewrite_title_wikilinks(actor: actor, item: knowledge_item, old_title: old_title) if title_changed
        return knowledge_item
      end

      full_content      = Frontmatter.render(fm: fm, title: new_title, body: new_body)
      new_relative_path = relocated_path_if_needed(knowledge_item, new_title, new_type, title_changed, type_changed)

      write_with_optional_move(
        actor: actor, knowledge_item: knowledge_item,
        old_full_path: full_path, new_relative_path: new_relative_path,
        full_content: full_content, old_title: old_title, new_title: new_title
      )

      knowledge_item.update!(
        title:           new_title,
        item_type:       new_type,
        aliases:         Array(fm["aliases"]),
        tags:            Array(fm["tags"]),
        body:            new_body,
        first_name:      fm["first_name"],
        last_name:       fm["last_name"],
        orcid:           fm["orcid"],
        issuer:          ActiveModel::Type::Boolean.new.cast(fm["issuer"]) ? true : false,
        parent_org_uuid: KnowledgeIndexer.resolve_parent_org_uuid(fm["parent_org"]),
        file_path:       new_relative_path,
        content_hash:    Digest::SHA256.hexdigest(full_content),
        file_updated_at: Time.current,
        indexed_at:      Time.current
      )

      sync_associations(actor: actor, item: knowledge_item, fm: fm,
                        topics: topics, contacts: contacts, body: new_body)

      rewrite_title_wikilinks(actor: actor, item: knowledge_item, old_title: old_title) if title_changed
      knowledge_item
    end

    # Append-Session-Pfad fuer Chat-Workflow:
    # - liest existing Datei
    # - parsed Frontmatter, merged: updated_at neu, Topics/Tags Union
    # - haengt unter `## Session YYYY-MM-DD`-Heading den Addendum-Block an
    # - schreibt zurueck + Git-Commit
    # - Indexer aktualisiert beim naechsten Reindex automatisch
    def append_session(actor:, knowledge_item:, addendum:, session_at: Date.current,
                       frontmatter_merge: {})
      AccessGate.authorize!(actor: actor, resource_type: "KnowledgeItem", action: "update")

      # #241 Plan B: existing body + Frontmatter aus DB rekonstruiert.
      full_path = BASE_PATH.join(knowledge_item.file_path)
      body      = knowledge_item.body.to_s
      fm        = Reader.build_frontmatter_hash(knowledge_item)

      # Frontmatter mergen: updated_at neu, Topics/Tags Union, Title bleibt.
      fm = fm.merge("updated_at" => Time.current.iso8601)
      if (extra_topics = Array(frontmatter_merge[:topics] || frontmatter_merge["topics"])).any?
        fm["topics"] = (Array(fm["topics"]) | extra_topics).uniq
      end
      if (extra_tags = Array(frontmatter_merge[:tags] || frontmatter_merge["tags"])).any?
        fm["tags"] = (Array(fm["tags"]) | extra_tags).uniq
      end

      # Body-Append: bestehenden Body lassen, einen Trenner und
      # `## Session YYYY-MM-DD` davor, dann das Addendum.
      session_heading = "## Session #{session_at.strftime('%Y-%m-%d')}"
      addendum_clean  = addendum.to_s.strip
      new_body = body.to_s.rstrip + "\n\n" + session_heading + "\n\n" + addendum_clean + "\n"

      title = fm["title"].presence || knowledge_item.title
      full_content = Frontmatter.render(fm: fm, title: title, body: new_body)
      File.write(full_path, full_content)

      GitRepo.commit(actor: actor, file_path: knowledge_item.file_path,
                     message: "Append session #{session_at}: #{title}")

      knowledge_item.update!(
        content_hash:    Digest::SHA256.hexdigest(full_content),
        tags:            Array(fm["tags"]),
        body:            new_body,
        file_updated_at: Time.current,
        indexed_at:      Time.current
      )

      link_slugs(knowledge_item, actor: actor,
                 topic_slugs:   fm["topics"] || [],
                 contact_slugs: fm["contacts"] || [])

      knowledge_item
    end

    private

    # #650: Binär-Asset verschieben + Sidecar (.meta.yml) nachziehen —
    # die Asset-Datei selbst bleibt byte-identisch.
    def move_binary_asset!(actor:, knowledge_item:, fm:, new_relative_path:,
                           old_title:, new_title:)
      old_path = knowledge_item.file_path
      old_full = BASE_PATH.join(old_path)
      new_full = BASE_PATH.join(new_relative_path)
      changed  = new_relative_path != old_path

      if changed
        FileUtils.mkdir_p(File.dirname(new_full))
        FileUtils.mv(old_full, new_full) if File.exist?(old_full) && new_full != old_full
      end

      old_sidecar = "#{old_path}.meta.yml"
      new_sidecar = "#{new_relative_path}.meta.yml"
      sidecar_fm  = fm.merge("title" => new_title, "updated_at" => Time.current.iso8601).compact
      File.write(BASE_PATH.join(new_sidecar), sidecar_fm.to_yaml)
      if changed && File.exist?(BASE_PATH.join(old_sidecar))
        File.delete(BASE_PATH.join(old_sidecar))
      end

      paths = changed ? [old_path, new_relative_path, old_sidecar, new_sidecar].uniq : [new_sidecar]
      GitRepo.commit(actor: actor, file_path: paths,
                     message: changed ? "Move asset: #{old_title} → #{new_title}" : "Update asset meta: #{new_title}")
    end

    def relocated_path_if_needed(knowledge_item, new_title, new_type, title_changed, type_changed)
      return knowledge_item.file_path unless title_changed || type_changed
      Paths.unique_relative_path(
        subdir: Paths.type_to_subdir(new_type),
        slug:   new_title.parameterize.presence || "note"
      )
    end

    def write_with_optional_move(actor:, knowledge_item:, old_full_path:,
                                 new_relative_path:, full_content:,
                                 old_title:, new_title:)
      if new_relative_path != knowledge_item.file_path
        old_path = knowledge_item.file_path
        new_full = BASE_PATH.join(new_relative_path)
        FileUtils.mkdir_p(File.dirname(new_full))
        File.write(new_full, full_content)
        File.delete(old_full_path) if File.exist?(old_full_path) && new_full != old_full_path
        GitRepo.commit(actor: actor, file_path: [old_path, new_relative_path],
                       message: "Move: #{old_title} → #{new_title}")
      else
        # #477 (Hans, 2026-06-02): Verzeichnis sicherstellen, bevor
        # geschrieben wird. Migrierte Task-Kommentare (Reply-KIs in
        # knowledge/replies/) haben nie eine Datei bekommen — das
        # Verzeichnis existiert nicht. Jede Schreib-Operation (z.B.
        # wrap_highlight beim Selektions-Anker) lief sonst in ENOENT, und
        # „Aufgabe aus Selektion in einer Antwort" warf einen Fehler. Die
        # Datei (DB ist Quelle der Wahrheit, Datei = Export) wird hier
        # just-in-time angelegt.
        FileUtils.mkdir_p(File.dirname(old_full_path))
        File.write(old_full_path, full_content)
        GitRepo.commit(actor: actor, file_path: knowledge_item.file_path,
                       message: "Update: #{new_title}")
      end
    end

    # Topics/Mentions aus den uebergebenen Slugs syncen, Wikilinks im Body
    # reindizieren, Person/Org-Frontmatter (Affiliations, Relationships,
    # ContactPoints) in die DB spiegeln.
    def sync_associations(actor:, item:, fm:, topics:, contacts:, body:)
      link_slugs(item, actor: actor,
                 topic_slugs:   topics   || item.topics.pluck(:slug),
                 contact_slugs: contacts || item.mentioned_kis.map { |k| k.title.parameterize })
      KnowledgeIndexer.index_body_references_for(item, body)
      KnowledgeIndexer.resolve_dangling_references_to(item.title, item.uuid)
      RelationSync.sync(item, body)
      PersonOrgSync.sync(item, fm) if item.item_type.in?(%w[person organization])
      # #384 Phase 2 (Hans, 2026-05-27): @-Mentions auf App-Nutzer.
      # #587: frisch erwaehnte Agenten poken (siehe create-Pfad).
      new_mention_ids = KnowledgeMarkdown::ActorMentions.sync_for(item, body)
      BuilderInboxPoke.poke_body_mentions(item, new_mention_ids, except: actor)
      # #466 (Hans, 2026-06-02): Anker (Highlight-8-Hex + Block-6-Zeichen)
      # auch beim UPDATE reindizieren — bisher lief Anchors.sync_for nur
      # im create-Pfad, sodass per wrap_highlight/ensure_anchor erzeugte
      # Anker nie in KnowledgeItemAnchor landeten und `[[^anker]]` (z.B.
      # Absatz-Links aus Antworten) nicht aufloesten.
      KnowledgeMarkdown::Anchors.sync_for(item, body)
    end

    # Sucht alle Backlink-Quellen mit Title-basiertem `[[Alter Titel]]`-
    # Wikilink und ersetzt den Title-Teil durch den neuen. UUID-Form-
    # Wikilinks bleiben unveraendert.
    def rewrite_title_wikilinks(actor:, item:, old_title:)
      refs = KnowledgeItemReference.where(target_uuid: item.uuid)
                                   .where("LOWER(target_title) = ?", old_title.downcase)
                                   .includes(:source, :source_task)
      sources      = refs.filter_map(&:source).uniq
      task_sources = refs.filter_map(&:source_task).uniq

      re = /\[\[(#{Regexp.escape(old_title)})((?:#[^\]|]+)?(?:\^[^\]|]+)?(?:\|[^\]]+)?)\]\]/i

      # #953 Folge: Titel-Wikilinks in Task-BESCHREIBUNGEN mit-rewriten —
      # das update! triggert den Description-Reindex, die Refs ziehen nach.
      task_sources.each do |task|
        new_desc = task.description.to_s.gsub(re) { "[[#{item.title}#{Regexp.last_match(2)}]]" }
        task.update!(description: new_desc) if new_desc != task.description.to_s
      end

      return if sources.empty?
      sources.each do |src|
        next if src.uuid == item.uuid  # Selbst-Verweis: nicht relevant
        raw = Reader.read(actor: actor, knowledge_item: src)
        fm, body = MarkdownFrontmatter.parse(raw)
        new_body = body.gsub(re) { "[[#{item.title}#{Regexp.last_match(2)}]]" }
        next if new_body == body  # nichts zu rewrite

        fm = fm.merge("updated_at" => Time.current.iso8601)
        title_for_h1 = fm["title"].presence || src.title
        full = Frontmatter.render(fm: fm.compact, title: title_for_h1, body: new_body)
        File.write(BASE_PATH.join(src.file_path), full)
        GitRepo.commit(actor: actor, file_path: src.file_path,
                       message: "Wikilink-Rewrite: #{old_title} → #{item.title}")
        # #241 Plan B: DB.body ist SoT — Wikilink-Rewrite muss auch dort
        # ankommen, sonst zeigt Reader die alten Titel weiter an.
        src.update!(body: new_body, content_hash: Digest::SHA256.hexdigest(full),
                    file_updated_at: Time.current)
        KnowledgeItemReference.where(source_uuid: src.uuid)
                              .where("LOWER(target_title) = ?", old_title.downcase)
                              .update_all(target_title: item.title, target_uuid: item.uuid)
      end
    end

    def link_slugs(item, actor:, topic_slugs:, contact_slugs:)
      Array(topic_slugs).each do |slug|
        next if slug.blank?
        topic = Topic.find_or_create_from_slug!(slug, creator: actor)
        item.knowledge_item_topics.find_or_create_by!(topic: topic)
      end
      Array(contact_slugs).each do |slug|
        next if slug.blank?
        mentioned = PersonKiResolver.find_or_create!(slug, actor: actor)
        next unless mentioned
        next if mentioned.uuid == item.uuid # selbst-Mention ueberspringen
        item.knowledge_item_mentions.find_or_create_by!(mentioned_uuid: mentioned.uuid)
      end
    end
  end
end
