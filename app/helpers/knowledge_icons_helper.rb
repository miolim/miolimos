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

  # Icon für einen item_type-String ODER ein KnowledgeItem.
  #
  # #840: Wird ein KnowledgeItem übergeben und ist es eine Person, kodiert
  # das Haupt-Icon den Status in Form UND Farbe (siehe person_status_icon).
  # Für alle anderen Typen (und für bare Type-Strings, z.B. Type-Picker-
  # Optionen) bleibt das Verhalten unverändert.
  def knowledge_type_icon(item_or_type, size: "w-4 h-4", known_via_comm: nil, **opts)
    if item_or_type.respond_to?(:item_type)
      ki = item_or_type
      return person_status_icon(ki, size: size, known_via_comm: known_via_comm, **opts) if ki.person?
      item_type = ki.item_type
    else
      item_type = item_or_type
    end
    name = KNOWLEDGE_TYPE_ICONS[item_type.to_s] || "file_text"
    icon(name, size: size, **opts)
  end

  # #840: Personen-Haupticon mit Status-Look. Präzedenz: manuell
  # „persönlich bekannt" (grün, user-check) > Kommunikation vorhanden
  # (blau, user) > neutral (erbt Elternfarbe, user). Form UND Farbe
  # unterscheiden die Zustände (auch für Farbfehlsichtige lesbar).
  # known_via_comm gebatcht übergeben, sonst wird es bei Bedarf (nur wenn
  # nicht persönlich bekannt) einzeln ermittelt.
  def person_status_icon(ki, size: "w-4 h-4", known_via_comm: nil, **opts)
    base_class  = opts.delete(:class)
    given_title = opts.delete(:title)
    known = ki.personally_known?
    comm  = !known && (known_via_comm.nil? ? ki.known_via_communication? : known_via_comm)
    name  = known ? "user-check" : "user"
    color = known ? "text-emerald-600" : (comm ? "text-sky-600" : nil)
    title = given_title || if known
                             t("knowledge.person_status.known_title")
                           elsif comm
                             t("knowledge.person_status.comm_title")
                           end
    icon(name, size: size,
         class: [color, base_class].compact.join(" ").presence,
         title: title, **opts)
  end
end
