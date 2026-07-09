# #926 (Hans, 2026-07-09): „Dokumenterstellung als Verfahren" — das gemeinsame
# Verhalten aller Entitäten, die ein DIN-5008-Dokument ausgeben (heute
# Document = Anschreiben und Invoice = Rechnung/Angebot; nach dem Upstream-
# Merge z.B. auch das Mietverhältnis in immoos). Eine druckbare Entität
# trägt Parteien (Aussteller/Empfänger als Stammdaten-KIs), Projekt,
# freie Infoblock-Felder und festgeschriebene PDF-Stände (Artefakte) —
# das eigentliche Rendern übernimmt DocumentRenderer.
#
# Erwartete Spalten: status, issuer_uuid, recipient_uuid,
# recipient_address_id, topic_id, creator_id, document_date,
# shown_identifier_ids (int[]), deleted_at.
module Printable
  extend ActiveSupport::Concern

  included do
    enum :status, { entwurf: 0, final: 1 }, default: :entwurf

    belongs_to :issuer,    class_name: "KnowledgeItem", foreign_key: :issuer_uuid,
                           primary_key: :uuid, optional: true
    belongs_to :recipient, class_name: "KnowledgeItem", foreign_key: :recipient_uuid,
                           primary_key: :uuid, optional: true
    # #694: pro Dokument gewählte Empfänger-Postadresse (bei mehreren
    # Postadressen). nil = automatisch (recipient.mailing_address).
    belongs_to :recipient_address, class_name: "PostalAddress", optional: true
    belongs_to :topic,   optional: true
    belongs_to :creator, class_name: "Actor", optional: true

    # #532: freie Key-Value-Felder (Informationsblock) — seit #926 polymorph.
    has_many :document_fields, -> { ordered }, as: :fieldable, dependent: :destroy
    # #532: festgeschriebene PDF-Stände (bei Status final) — seit #926 die
    # EINE gemeinsame Artefakt-Schicht aller druckbaren Entitäten.
    has_many :document_artifacts, -> { recent }, as: :printable, dependent: :destroy

    # #787: Soft-Delete (Papierkorb) wie bei KnowledgeItem/Task.
    default_scope { where(deleted_at: nil) }
    scope :with_discarded, -> { unscope(where: :deleted_at) }
    scope :discarded,      -> { with_discarded.where.not(deleted_at: nil) }
    scope :recent,         -> { order(created_at: :desc) }
  end

  def discard!   = update_columns(deleted_at: Time.current)
  def undiscard! = update_columns(deleted_at: nil)
  def discarded? = deleted_at.present?

  # #532: final = gesperrt; andere Felder dürfen nicht geändert werden,
  # bis der Status wieder auf Entwurf gesetzt wird.
  def locked? = final?

  # #694: die explizit gewählte Empfänger-Postadresse — aber nur, wenn sie
  # auch zum aktuellen Empfänger gehört (schützt vor Stale-Wahl nach
  # Empfänger-Wechsel). nil → automatisch (recipient.mailing_address).
  def chosen_recipient_address
    recipient_address if recipient_address && recipient_address.knowledge_item_uuid == recipient_uuid
  end

  # #532: ID-Felder (#544), die diese Aussteller↔Empfänger-Beziehung betreffen
  # und im Dokument angeboten/angezeigt werden können:
  #   - Nummern des AUSSTELLERS bei DIESEM Empfänger (z.B. meine Versicherten-
  #     nummer bei der Kasse) — der häufigste Fall im Anschreiben
  #   - eigenständige Nummern des Ausstellers (z.B. Steuernummer, ohne Gegenseite)
  #   - Nummern des EMPFÄNGERS bei MIR (z.B. die Kundennummer, die ich ihm gab)
  def identifier_candidates
    cands = []
    cands += issuer.identifiers.to_a.select { |i| i.counterparty_uuid == recipient_uuid || i.counterparty_uuid.nil? } if issuer
    cands += recipient.identifiers.to_a.select { |i| i.counterparty_uuid == issuer_uuid } if recipient
    cands.uniq(&:id)
  end

  # #532: die per Checkbox ausgewählten ID-Felder (aus den Kandidaten).
  def shown_identifiers
    return [] if shown_identifier_ids.blank?
    Identifier.where(id: shown_identifier_ids).ordered.to_a
  end

  # Alle Key-Value-Zeilen für den Informationsblock: freie Felder + die
  # ausgewählten IDs. Liefert [[label, value], …].
  def info_fields
    document_fields.map { |f| [f.label, f.value] } +
      shown_identifiers.map { |i| [i.label, i.value] }
  end

  # #541: USt-Befreiung hängt am ausstellenden Kontakt (z.B. Kleinunternehmer
  # §19 UStG). Greift sie, wird keine Umsatzsteuer ausgewiesen.
  def vat_exempt? = !!issuer&.vat_exempt?

  # ── #541 Compliance: Aussteller-Pflichtangaben aus dem Aussteller-KI ──────
  # Steuernummer/USt-IdNr (§14 UStG Pflicht). Liefert [[label, value], …].
  def issuer_tax_ids
    return [] unless issuer
    issuer.identifiers.to_a
          .select { |i| i.label.to_s =~ /ust.?-?id|umsatzsteuer|vat|steuer\s*-?\s*(nr|nummer|id)/i }
          .map { |i| [i.label, i.value] }
  end

  # IBAN des Ausstellers (für den Zahlungsblock). Optional BIC.
  def issuer_iban = issuer&.identifiers&.to_a&.find { |i| i.label.to_s =~ /iban/i }&.value
  def issuer_bic  = issuer&.identifiers&.to_a&.find { |i| i.label.to_s =~ /\bbic\b|swift/i }&.value

  # ── Verfahren-Hooks (DocumentRenderer / Output-Actions) ──────────────────
  # Mehrseitiger Render mit Fußzeile pro Seite (Ferrum/CDP)? Default: nein.
  def print_paged? = false
  # Dokument-ID für die Fußzeile des paged-Renders (nur wenn print_paged?).
  def print_doc_id = nil

  # #926 Stufe 2: Merge-Kontext für {{key}}-Platzhalter im Vorlagentext.
  # Gemeinsame Schlüssel + die Infoblock-Felder (Label → Wert); Entitäten
  # ergänzen ihre eigenen (z.B. betreff/nummer) via super.merge(…).
  def merge_context
    ctx = {
      "aussteller" => issuer&.title,
      "empfaenger" => recipient&.title,
      "datum"      => (I18n.l(document_date, format: :long) if respond_to?(:document_date) && document_date),
      "projekt"    => topic&.name
    }
    info_fields.each { |label, value| ctx[TemplateMerge.normalize_key(label)] = value }
    ctx.compact
  end
end
