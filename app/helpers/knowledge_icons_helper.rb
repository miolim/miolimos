# #203 Phase E.6: KI-Type → Lucide-Icon-Name Mapping.
module KnowledgeIconsHelper
  KNOWLEDGE_TYPE_ICONS = {
    "note"           => "file_text",
    "abstract"       => "bookmark",
    "transcript"     => "file",
    "direct_quote"   => "quote",
    "indirect_quote" => "quote",
    "comment"        => "message_square",
    "person"         => "user",
    "organization"   => "building",
    "doc"            => "manual",
    "synthesis"      => "book_open",  # #155 Phase 5b: Synthese-Notiz
    "image"          => "image",      # #609 v3: Bild-KI
    # Bestand-Aliase: Frontmatter mit alten type-Strings findet bis
    # zum Backfill noch ein Icon — danach unbenutzt.
    "ai_chat"  => "bookmark",
    "web_clip" => "file",
    "quote"    => "quote",
    "document" => "file"
  }.freeze

  def knowledge_type_icon(item_type, size: "w-4 h-4", **opts)
    name = KNOWLEDGE_TYPE_ICONS[item_type.to_s] || "file_text"
    icon(name, size: size, **opts)
  end
end
