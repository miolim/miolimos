# #1321 (Hans, 2026-08-07): Darstellung einer Trefferzeile — Titel, Zweitzeile
# und Sprungziel je Sammlung. Dropdown und Ergebnis-Card rendern dieselbe
# Zeile; was sich zwischen den Sammlungen unterscheidet, steht nur hier.
module SearchHelper
  SECTION_ICONS = {
    tasks:           "tasks",
    contacts:        "users",
    communications:  "communications",
    knowledge_items: "knowledge",
    replies:         "message_square",
    documents:       "file_text",
    invoices:        "banknote",
    topics:          "tag",
    sources:         "book_open",
    awaitings:       "waiting",
    inbox_items:     "inbox"
  }.freeze

  def search_section_label(section)
    t("search.sections.#{section}")
  end

  def search_section_icon(section, size: "w-4 h-4")
    icon(SECTION_ICONS.fetch(section, "search"), size: size)
  end

  # Sprungziel einer Zeile: kind/id für blade-link (hängt die Card an den
  # Stack) plus href als Fallback auf Seiten ohne Stack — genau die
  # Aufteilung, die blade_link_controller erwartet.
  def search_row_target(section, record)
    case section
    when :tasks
      { kind: "task", id: record.id, href: task_path(record) }
    when :contacts, :knowledge_items
      { kind: "ki", id: record.uuid, href: knowledge_items_path(stack: record.uuid) }
    when :communications
      { kind: "communication", id: record.id, href: communication_path(record) }
    when :documents
      { kind: "document", id: record.id, href: documents_path(stack: "document:#{record.id}") }
    when :invoices
      { kind: "invoice", id: record.id, href: invoices_path(stack: "invoice:#{record.id}") }
    when :topics
      # Ein Thema öffnet als Reiter-Blade (list:topic:<slug>) — dasselbe
      # Blade wie aus der Themen-Liste, nicht das Legacy-Detail.
      { kind: "topic_list", id: record.slug, href: topic_path(record.slug) }
    when :sources
      { kind: "source", id: record.slug, href: source_path(record.slug) }
    when :awaitings
      { kind: "awaiting", id: record.id, href: awaitings_path(stack: "awaiting:#{record.id}") }
    when :inbox_items
      { kind: "inbox_item", id: record.id, href: inbox_items_path(stack: "inboxitem:#{record.id}") }
    end
  end

  def search_row_title(section, record)
    case section
    when :tasks           then record.title
    when :contacts        then record.display_name
    when :knowledge_items then record.title
    when :communications  then record.subject.presence || t("search.no_subject")
    when :documents       then record.display_name.presence || t("documents.list.unnamed")
    when :invoices        then record.display_name.presence || t("search.no_subject")
    when :topics          then record.name
    when :sources         then record.title
    when :awaitings       then record.title
    when :inbox_items     then record.display_title
    end
  end

  # Zweitzeile: das eine Feld, das den Treffer einordnet (Datum, Herkunft).
  # nil = keine Zweitzeile; der Snippet steht ohnehin darunter.
  def search_row_meta(section, record)
    case section
    when :communications
      record.sent_at && l(record.sent_at.to_date, format: :default)
    when :documents, :invoices
      record.document_date && l(record.document_date, format: :default)
    when :awaitings
      t("search.follow_up_on", date: l(record.follow_up_at, format: :default))
    when :sources
      [record.display_authors.presence, record.display_year.presence].compact.join(" · ").presence
    when :inbox_items
      [record.source_kind.presence, l(record.created_at.to_date, format: :default)].compact.join(" · ")
    end
  end

  # Snippet-Map ist nach dem Primärschlüssel gekeyt — KIs über uuid, alles
  # andere über id.
  def search_snippet(snippets, record)
    snippets[record.public_send(record.class.primary_key)]
  end

  # Frame-Id einer Sektion. Der Payload steckt als Kurz-Digest drin, damit
  # zwei Ergebnis-Cards mit verschiedenen Suchbegriffen im selben Stack nicht
  # in denselben Frame rendern.
  def search_section_frame_id(payload, section)
    "search_sec_#{section}_#{Digest::MD5.hexdigest(payload.to_s)[0, 8]}"
  end

  # Das Icon links in der Zeile. KIs tragen ihr Typ-Icon (Notiz, Bild,
  # Person …), alles andere das Sammlungs-Icon.
  def search_row_icon(section, record)
    return knowledge_type_icon(record) if %i[contacts knowledge_items].include?(section)
    search_section_icon(section)
  end
end
