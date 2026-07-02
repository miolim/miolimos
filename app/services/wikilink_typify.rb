# #239 Phase B+: Fuegt einen Relation-Anchor (^abc123) in den N-ten
# Wikilink im Body einer KnowledgeItem ein, speichert den Body und
# triggert RelationSync. Idempotent NICHT — jeder Aufruf erzeugt einen
# neuen anchor_id.
#
# Skip-Regel (#312 follow-up, 2026-05-23): nur dann skippen, wenn fuer
# (source, anchor) bereits eine Relation existiert. Block-Anker-Wikilinks
# (anchor zeigt auf einen Absatz im TARGET, nicht auf eine Relation im
# SOURCE) sind ab jetzt upgradebar — das Backlinks-Popover-Ketten-Icon
# loest exakt diesen Pfad aus.
class WikilinkTypify
  WIKILINK_RE = KnowledgeMarkdown::Wikilinks::WIKILINK_RE

  Result = Struct.new(:anchor_id, :target_uuid, :target_title, :body, keyword_init: true)

  def self.call(actor:, knowledge_item:, occurrence:)
    AccessGate.authorize!(actor: actor, resource_type: "KnowledgeItem", action: "update")

    body = knowledge_item.body.to_s
    idx = 0
    new_anchor = nil
    target_uuid = nil
    target_title = nil

    new_body = body.gsub(WIKILINK_RE) do
      idx += 1
      full = Regexp.last_match(0)
      next full unless idx == occurrence

      target_id  = Regexp.last_match(1).strip
      heading    = Regexp.last_match(2)
      block_anch = Regexp.last_match(3)
      alias_raw  = Regexp.last_match(4)

      # Schon typed Relation? → no-op. Block-Anker dagegen ist
      # upgradebar (anchor zeigt nur auf einen Absatz im Target, nicht
      # auf eine Relation am Source).
      if block_anch && Relation.exists?(source_uuid: knowledge_item.uuid, anchor_id: block_anch)
        next full
      end

      target = KnowledgeMarkdown::Wikilinks.lookup_target(target_id)
      next full unless target

      new_anchor   = Relation.generate_anchor_id(source_uuid: knowledge_item.uuid)
      target_uuid  = target.uuid
      target_title = target.title

      inner = String.new(target_id)
      inner << "##{heading}" if heading
      inner << "^#{new_anchor}"
      inner << "|#{alias_raw}" if alias_raw
      "[[#{inner}]]"
    end

    return nil unless new_anchor

    # Body-Update + RelationSync. Persist als DB.body (Plan B SoT) und
    # File-Mirror via FileProxy.update bleibt aus: das modifiziert auch
    # Frontmatter/Indices, hier wollen wir nur Body. Schreiben direkt,
    # GitRepo-Commit, Indexer-Re-Index analog zum rewrite_title_wikilinks-
    # Pfad.
    full_path  = FileProxy::BASE_PATH.join(knowledge_item.file_path)
    fm         = FileProxy::Reader.build_frontmatter_hash(knowledge_item)
    title      = fm["title"].presence || knowledge_item.title
    content    = FileProxy::Frontmatter.render(fm: fm, title: title, body: new_body)
    File.write(full_path, content)
    FileProxy::GitRepo.commit(actor: actor, file_path: knowledge_item.file_path,
                              message: "Typify Wikilink ^#{new_anchor}: #{knowledge_item.title}")

    knowledge_item.update!(body: new_body,
                           content_hash: Digest::SHA256.hexdigest(content),
                           file_updated_at: Time.current,
                           indexed_at: Time.current)

    KnowledgeIndexer.index_body_references_for(knowledge_item, new_body)
    RelationSync.sync(knowledge_item, new_body)

    Result.new(anchor_id: new_anchor, target_uuid: target_uuid,
               target_title: target_title, body: new_body)
  end

  # #312 follow-up: Typify-by-Block-Anker. Scant den Body nach dem ersten
  # Wikilink, dessen Block-Anker `target_anchor` lautet UND der auf
  # `target_uuid` aufloest. Delegiert dann an `.call(occurrence: …)`.
  # Aufrufer ist das Ketten-Icon im Backlinks-Popover, das nur source +
  # target + anchor kennt, nicht die Position im Body.
  def self.call_for_target_anchor(actor:, knowledge_item:, target_uuid:, target_anchor:)
    body = knowledge_item.body.to_s
    occurrence = nil
    idx = 0
    body.gsub(WIKILINK_RE) do
      idx += 1
      tgt_id     = Regexp.last_match(1).strip
      block_anch = Regexp.last_match(3)
      if occurrence.nil? && block_anch == target_anchor
        tgt = KnowledgeMarkdown::Wikilinks.lookup_target(tgt_id)
        occurrence = idx if tgt && tgt.uuid == target_uuid
      end
      Regexp.last_match(0)
    end
    return nil unless occurrence
    call(actor: actor, knowledge_item: knowledge_item, occurrence: occurrence)
  end
end
