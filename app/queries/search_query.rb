# #1321 (Hans, 2026-08-07): DIE eine Definition dessen, was „Suche" in
# miolimOS bedeutet. Vorher lag sie inline im SearchController und kannte nur
# fünf Sammlungen — Dokumente, Rechnungen, Themen, Quellen, Wiedervorlagen und
# Inbox waren gar nicht auffindbar, Kommunikation nur über den Betreff. Das
# Dropdown (SearchController#index) und die Ergebnis-Card (#list_card/#section)
# lesen beide hier; eine neue Sammlung wird genau EINMAL eingetragen.
#
# Volltext (Postgres FTS über search_vector + ts_rank_cd + ts_headline) gibt es
# nur für Tasks und KnowledgeItems — die beiden großen Tabellen. Alle anderen
# Sammlungen sind klein (< 200 Zeilen in Prod), dort reicht LOWER(…) LIKE;
# ein tsvector samt Trigger wäre Aufwand ohne Gegenwert. Der Snippet-Ausschnitt
# entsteht für sie in Ruby (#excerpt_html) statt über ts_headline.
#
# #602 S1: JEDE Sammlung läuft durch ihren visible_to-Scope. Ausnahme mit
# Ansage: Source kennt keinen — Quellen sind in miolimOS global (kein
# Topic-Bezug, kein visible_via). Bekommt Source je Sichtbarkeit, greift der
# Scope hier automatisch, sobald er existiert.
class SearchQuery
  MIN_LENGTH = 2
  # Zeilen je Sektion, die die Ergebnis-Card zunächst lädt (#1321).
  PAGE_SIZE  = 20

  # Reihenfolge = Reihenfolge im Dropdown UND in der Ergebnis-Card. Hans zu
  # #1321: „wie heute" — die fünf bekannten Sektionen zuerst, die neuen dahinter.
  SECTIONS = %i[
    tasks contacts communications knowledge_items replies
    documents invoices topics sources awaitings inbox_items
  ].freeze

  # Sammlungen mit Postgres-Volltext (search_vector). Nur die bekommen
  # ts_rank_cd-Sortierung und ts_headline-Snippets.
  FTS_SECTIONS = %i[tasks contacts knowledge_items replies].freeze

  # Payload = base64url(suchbegriff), siehe SearchController-Kopf.
  BadPayload = Class.new(StandardError)

  def self.encode_payload(query)
    Base64.urlsafe_encode64(query.to_s, padding: false)
  end

  def self.decode_payload(payload)
    raw = begin
      Base64.urlsafe_decode64(payload.to_s)
    rescue ArgumentError
      raise BadPayload
    end
    # #1058: urlsafe_decode64 liefert BINARY — ohne force_encoding knallen
    # Umlaute im Suchbegriff beim Rendern (Encoding::CompatibilityError).
    raw = raw.dup.force_encoding(Encoding::UTF_8)
    raise BadPayload unless raw.valid_encoding?
    raw
  end

  attr_reader :query, :actor

  def initialize(query, actor:)
    @query   = query.to_s.strip
    @actor   = actor
    @counts  = {}
    @records = {}
  end

  # Unter MIN_LENGTH suchen wir gar nicht — sonst liefert jede zweite
  # Tastatureingabe die halbe Datenbank.
  def blank? = query.length < MIN_LENGTH

  def count(section)
    return 0 if blank?
    @counts[section] ||= scope(section).count
  end

  def counts = SECTIONS.index_with { |s| count(s) }

  def total = SECTIONS.sum { |s| count(s) }

  def any? = SECTIONS.any? { |s| count(s).positive? }

  # Sektionen mit mindestens einem Treffer — die Card zeigt nur die.
  def hit_sections = SECTIONS.select { |s| count(s).positive? }

  def records(section, limit:)
    return [] if blank?
    @records[[section, limit]] ||= relation(section).limit(limit).to_a
  end

  # Primärschlüssel => Snippet-HTML (mit <mark>). Für FTS-Sammlungen aus
  # ts_headline (eine Query je Sammlung, nicht je Zeile — ts_headline ist
  # teuer), für die LIKE-Sammlungen aus einem Ruby-Ausschnitt.
  def snippets(section, records)
    return {} if records.empty?
    if FTS_SECTIONS.include?(section)
      headline_map(records, headline_sql(section))
    else
      records.index_by(&:id).transform_values { |r| excerpt_html(excerpt_source(section, r)) }
    end
  end

  # #395: Reply-KIs haben keinen eigenen Titel — die Trefferzeile zeigt den
  # Eltern-Datensatz (Task oder KI) und verlinkt auf dessen Anker. Eltern
  # vorab in einem Rutsch laden, nicht je Zeile.
  def reply_parents(replies)
    task_ids = replies.select { |r| r.parent_type == "Task" }.map(&:parent_id_int)
    ki_uuids = replies.select { |r| r.parent_type == "KnowledgeItem" }.map(&:parent_uuid)
    map = {}
    Task.visible_to(actor).where(id: task_ids).each { |t| map[["Task", t.id]] = t } if task_ids.any?
    if ki_uuids.any?
      KnowledgeItem.visible_to(actor).where(uuid: ki_uuids).each { |k| map[["KnowledgeItem", k.uuid]] = k }
    end
    map
  end

  # Escapter Textausschnitt rund um den ersten Treffer, Fundstelle in <mark>.
  # Für die LIKE-Sammlungen, die kein ts_headline haben.
  def excerpt_html(text, window: 60)
    text = text.to_s.tr("\n", " ").squeeze(" ").strip
    return nil if text.blank?
    needle = query.downcase
    at     = text.downcase.index(needle)
    return nil if at.nil?

    from   = [at - window, 0].max
    to     = [at + needle.length + window, text.length].min
    before = ERB::Util.html_escape(text[from...at])
    hit    = ERB::Util.html_escape(text[at, needle.length])
    after  = ERB::Util.html_escape(text[(at + needle.length)...to])
    lead   = from.positive? ? "…" : ""
    trail  = to < text.length ? "…" : ""
    "#{lead}#{before}<mark>#{hit}</mark>#{after}#{trail}".html_safe
  end

  private

  # ── Sammlungen ────────────────────────────────────────────────────────
  # scope(section) ist UNSORTIERT (für count — ein ORDER BY ts_rank_cd in
  # einer Aggregat-Query wirft in Postgres einen GROUP-BY-Fehler);
  # relation(section) legt die Sortierung obendrauf.

  def scope(section)
    case section
    when :tasks           then tasks_scope
    when :contacts        then contacts_scope
    when :communications  then communications_scope
    when :knowledge_items then knowledge_items_scope
    when :replies         then replies_scope
    when :documents       then documents_scope
    when :invoices        then invoices_scope
    when :topics          then topics_scope
    when :sources         then sources_scope
    when :awaitings       then awaitings_scope
    when :inbox_items     then inbox_items_scope
    else raise ArgumentError, "unknown search section #{section.inspect}"
    end
  end

  def relation(section)
    rel = scope(section)
    case section
    when :tasks
      # #481: „#<nr>" stellt die Aufgabe mit dieser Nummer vorne ein.
      rel.order(Arel.sql("#{direct_task_id ? "CASE WHEN tasks.id = #{direct_task_id.to_i} THEN 1 ELSE 0 END DESC, " : ""}ts_rank_cd(search_vector, #{tsq}) DESC, tasks.id DESC"))
    when :contacts
      rel.order(Arel.sql("ts_rank_cd(search_vector, #{tsq}) DESC, LOWER(title)"))
    when :knowledge_items, :replies
      rel.order(Arel.sql("ts_rank_cd(search_vector, #{tsq}) DESC"))
    when :communications  then rel.order(Arel.sql("sent_at DESC NULLS LAST, id DESC"))
    when :documents       then rel.order(Arel.sql("document_date DESC NULLS LAST, id DESC"))
    when :invoices        then rel.order(Arel.sql("document_date DESC NULLS LAST, id DESC"))
    when :topics          then rel.order(Arel.sql("LOWER(name)"))
    when :sources         then rel.order(Arel.sql("LOWER(title)"))
    when :awaitings       then rel.order(follow_up_at: :desc, id: :desc)
    when :inbox_items     then rel.order(created_at: :desc)
    end
  end

  def tasks_scope
    if direct_task_id
      Task.visible_to(actor).where("search_vector @@ #{tsq} OR tasks.id = ?", direct_task_id)
    else
      Task.visible_to(actor).where("search_vector @@ #{tsq}")
    end
  end

  # Personen/Organisationen: Volltext ODER Treffer in einem Kontaktweg
  # (E-Mail, Telefon …) — die stehen in contact_points, nicht im KI-Body.
  def contacts_scope
    KnowledgeItem.visible_to(actor).persons_and_orgs
                 .where("search_vector @@ #{tsq} OR uuid IN (:cp)", cp: contact_point_uuids)
  end

  def knowledge_items_scope
    KnowledgeItem.visible_to(actor)
                 .where.not(item_type: [:person, :organization, :reply])
                 .where("search_vector @@ #{tsq}")
  end

  # #395: Antworten (Reply-KIs) als eigene Sektion. Nur veröffentlichte —
  # Entwürfe bleiben privat.
  def replies_scope
    KnowledgeItem.visible_to(actor)
                 .where(item_type: :reply).where.not(published_at: nil)
                 .where("search_vector @@ #{tsq}")
  end

  # #1321: vorher nur `subject LIKE` — der Nachrichtentext war unsichtbar.
  def communications_scope
    Communication.visible_to(actor).where(
      "LOWER(COALESCE(subject, '')) LIKE :l OR LOWER(COALESCE(body, '')) LIKE :l", l: like
    )
  end

  # Der Fließtext eines Anschreibens lebt in seiner Body-KI. Ohne den
  # Unterquery wäre ein Brief nur über seinen Betreff auffindbar — und der
  # Textfund erschiene als Wissens-Treffer statt als Dokument.
  def documents_scope
    Document.visible_to(actor).where(
      "LOWER(COALESCE(subject, '')) LIKE :l OR LOWER(COALESCE(recipient_label, '')) LIKE :l " \
      "OR LOWER(COALESCE(your_ref, '')) LIKE :l OR LOWER(COALESCE(our_ref, '')) LIKE :l " \
      "OR body_ki_uuid IN (SELECT uuid FROM knowledge_items WHERE search_vector @@ #{tsq})",
      l: like
    )
  end

  def invoices_scope
    Invoice.visible_to(actor).where(
      "LOWER(COALESCE(subject, '')) LIKE :l OR LOWER(COALESCE(number, '')) LIKE :l " \
      "OR LOWER(COALESCE(your_ref, '')) LIKE :l OR LOWER(COALESCE(our_ref, '')) LIKE :l",
      l: like
    )
  end

  def topics_scope
    Topic.visible_to(actor).where(
      "LOWER(name) LIKE :l OR LOWER(slug) LIKE :l OR LOWER(COALESCE(description, '')) LIKE :l", l: like
    )
  end

  def sources_scope
    Source.where(
      "LOWER(title) LIKE :l OR LOWER(slug) LIKE :l OR LOWER(COALESCE(container_title, '')) LIKE :l " \
      "OR LOWER(COALESCE(publisher, '')) LIKE :l OR LOWER(COALESCE(abstract, '')) LIKE :l",
      l: like
    )
  end

  def awaitings_scope
    Awaiting.visible_to(actor).where(
      "LOWER(title) LIKE :l OR LOWER(COALESCE(description, '')) LIKE :l " \
      "OR LOWER(COALESCE(resolution_note, '')) LIKE :l", l: like
    )
  end

  def inbox_items_scope
    InboxItem.visible_to(actor).where(
      "LOWER(COALESCE(title, '')) LIKE :l OR LOWER(COALESCE(raw_content, '')) LIKE :l " \
      "OR LOWER(COALESCE(source_url, '')) LIKE :l", l: like
    )
  end

  # ── Bausteine ─────────────────────────────────────────────────────────

  # websearch_to_tsquery erlaubt natürliche Eingaben: "foo bar",
  # "phrase in anführungszeichen", -ausschluss.
  def tsq
    @tsq ||= ActiveRecord::Base.sanitize_sql_array(["websearch_to_tsquery('german', ?)", query])
  end

  def like = @like ||= "%#{query.downcase}%"

  # #481 (Hans, 2026-06-03): „#477" findet die Aufgabe über ihre Nummer,
  # nicht nur über Textfelder. Optionaler Space nach dem #.
  def direct_task_id
    return @direct_task_id if defined?(@direct_task_id)
    m = query.match(/\A#\s*(\d+)\z/)
    @direct_task_id = m && Task.visible_to(actor).where(id: m[1].to_i).pick(:id)
  end

  def contact_point_uuids
    @contact_point_uuids ||= ContactPoint.where("LOWER(value) LIKE ?", like).pluck(:knowledge_item_uuid)
  end

  def headline_sql(section)
    case section
    when :tasks
      "ts_headline('german', coalesce(description, title), #{tsq}, " \
      "'StartSel=<mark>, StopSel=</mark>, MaxFragments=1, MaxWords=20, MinWords=5')"
    when :contacts
      "ts_headline('german', coalesce(body, ''), #{tsq}, " \
      "'StartSel=<mark>, StopSel=</mark>, MaxFragments=1, MaxWords=20, MinWords=5')"
    else
      "ts_headline('german', coalesce(body, ''), #{tsq}, " \
      "'StartSel=<mark>, StopSel=</mark>, MaxFragments=1, MaxWords=25, MinWords=5')"
    end
  end

  def headline_map(records, sql)
    klass = records.first.class
    pk    = klass.primary_key
    ids   = records.map(&pk.to_sym)
    klass.where(pk => ids).pluck(pk, Arel.sql(sql)).to_h
  end

  # Welches Feld eine LIKE-Sammlung für den Snippet-Ausschnitt hergibt —
  # das lange Textfeld, nicht der Titel (der steht schon in der Zeile).
  def excerpt_source(section, record)
    case section
    when :communications then record.body
    when :documents      then record.subject
    when :invoices       then record.subject
    when :topics         then record.description
    when :sources        then record.abstract
    when :awaitings      then record.description.presence || record.resolution_note
    when :inbox_items    then record.raw_content
    end
  end
end
