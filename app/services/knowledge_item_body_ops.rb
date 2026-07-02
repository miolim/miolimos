# Domain-Operationen am Markdown-Body eines KnowledgeItems, die der
# Controller nur durchreichen soll. Bündelt:
#
#   - resolve_anchor!  – `block-N` → stabiler `^id`, idempotent
#   - comment_at       – Comment-KI mit Wikilink-Header anlegen
#   - append_quote     – Quote-Sammel-KI für eine PDF/Document erweitern
#
# Der Aufrufer übergibt das Source-Item plus den ausführenden Actor; der
# Service kapselt FileProxy + KnowledgeBlockAnchor und gibt nur Daten
# zurück, kein HTTP-Layer.
class KnowledgeItemBodyOps
  def initialize(item, actor:)
    @item  = item
    @actor = actor
  end

  # Wandelt eine Anker-Anfrage (`block-N` oder bestehender Anker) in
  # eine stabile Anker-ID. Bei `block-N` wird ggf. ein neuer Anker
  # erzeugt und ans Source-Markdown gehängt. Wirft, wenn N außerhalb
  # liegt — Aufrufer sollte das als 422 abbilden.
  def resolve_anchor!(requested)
    if requested.start_with?("block-") && (n = requested.sub("block-", "").to_i) > 0
      anchor = block_anchor_service.ensure!(n)
      raise ArgumentError, "Block-Index #{n} außerhalb" if anchor.nil?
      anchor
    else
      requested
    end
  end

  # Comment-KI an einem Anker erzeugen. Liefert die neue KI zurück
  # (UUID + Anchor sind über das KI ablesbar).
  def comment_at(anchor)
    anchor     = resolve_anchor!(anchor)
    block_text = block_anchor_service.text_at(anchor)
    snippet    = block_text.split(/\s+/).first(4).join(" ").presence || @item.title
    title      = "Kommentar zu: #{snippet}"

    body = "[[#{@item.uuid}^#{anchor}|↳ #{@item.title}]]\n\n"
    comment = FileProxy.create(
      actor:     @actor,
      title:     title,
      item_type: :comment,
      content:   body,
      topics:    [], contacts: [], tags: ["kommentar"]
    )
    [comment, anchor]
  end

  # Quote-Sammel-KI für `@item` erweitern (PDF/Document → "Quotes aus
  # X"). Liefert das Sammel-KI plus ein Flag, ob es neu angelegt wurde
  # — der Caller braucht das für die UX-Antwort.
  def append_quote(text)
    text = text.to_s.strip
    raise ArgumentError, "Leerer Quote-Text" if text.empty?

    collection, created = find_or_create_quotes_collection
    body     = FileProxy.read_body(actor: @actor, knowledge_item: collection)
    appended = text.lines.map { |l| "> #{l.chomp}" }.join("\n")
    new_body = body.rstrip + "\n\n" + appended + "\n\n---\n"
    FileProxy.update(actor: @actor, knowledge_item: collection, content: new_body)

    [collection, created]
  end

  private

  # Findet (oder erstellt) das "Quotes aus X"-Sammel-KI für eine
  # gegebene PDF/Document. Lookup über Title-Convention plus Backlink-
  # Constraint, damit umbenannte Sammlungen nicht versehentlich gefunden
  # werden, wenn Title-Patterns kollidieren.
  def find_or_create_quotes_collection
    collection_title = "Quotes aus #{@item.title}"
    existing = KnowledgeItemReference
      .where(target_uuid: @item.uuid)
      .joins(:source)
      .where("knowledge_items.title = ?", collection_title)
      .first&.source
    return [existing, false] if existing

    # Der `[[uuid|↳ Title]]`-Wikilink im Body wird von FileProxy.create /
    # index_body_references_for automatisch als incoming-Ref auf das
    # Quell-KI angelegt.
    new_collection = FileProxy.create(
      actor:     @actor,
      title:     collection_title,
      item_type: :note,
      content:   "[[#{@item.uuid}|↳ #{@item.title}]]\n\n",
      topics: [], contacts: [], tags: ["quotes"]
    )
    [new_collection, true]
  end

  def block_anchor_service
    @block_anchor_service ||= KnowledgeBlockAnchor.new(@item, actor: @actor)
  end
end
