# #532 (Hans, 2026-06-08): Document = Kompositions-Objekt. Referenziert
# Aussteller/Empfänger (Person/Org-KIs = Stammdaten), optional einen
# Prosa-Body (KI, erbt Editor/Versionierung/Wikilinks) und ein Topic
# (Projekt). Rechnungen tragen strukturierte Positionen (invoice_lines),
# aus denen sich Netto/Steuer/Brutto + die EN16931-Steueraufschlüsselung
# (#541) ergeben. Sichtbare Ausgabe via DIN-5008-Theme (#532).
class Document < ApplicationRecord
  # #602 S1: sichtbar = eigene Dokumente + Dokumente sichtbarer Topics.
  include VisibleVia
  visible_via topic_column: :topic_id

  enum :kind,   { brief: 0, nda: 1, rechnung: 2, angebot: 3, lastschrift: 4 }  # #786: SEPA-Lastschriftmandat
  enum :status, { entwurf: 0, final: 1 }, default: :entwurf

  belongs_to :issuer,    class_name: "KnowledgeItem", foreign_key: :issuer_uuid,
                         primary_key: :uuid, optional: true
  belongs_to :recipient, class_name: "KnowledgeItem", foreign_key: :recipient_uuid,
                         primary_key: :uuid, optional: true
  # #694: pro Dokument gewählte Empfänger-Postadresse (bei mehreren
  # Postadressen). nil = automatisch (recipient.mailing_address).
  belongs_to :recipient_address, class_name: "PostalAddress", optional: true
  belongs_to :body_ki,   class_name: "KnowledgeItem", foreign_key: :body_ki_uuid,
                         primary_key: :uuid, optional: true
  # #786 Inkr.2: gewählte Bankverbindung des Schuldners (= Aussteller) fürs
  # SEPA-Mandat. Optional; nil → automatisch die erste Bankverbindung.
  belongs_to :debtor_bank_account, class_name: "BankAccount", optional: true
  belongs_to :topic,     optional: true
  belongs_to :creator,   class_name: "Actor", optional: true

  has_many :invoice_lines, -> { ordered }, dependent: :destroy
  # #532: freie Key-Value-Felder am Dokument (Informationsblock).
  has_many :document_fields, -> { ordered }, dependent: :destroy
  # #532: festgeschriebene PDF-Stände (bei Status final).
  has_many :document_artifacts, -> { recent }, dependent: :destroy

  validates :kind, presence: true

  # #787 (Hans): Soft-Delete (Papierkorb) wie bei KnowledgeItem/Task. Gelöschte
  # sind per default ausgeblendet; restore über undiscard!. Finale PDFs
  # (Artefakte) werden separat hart gelöscht.
  default_scope { where(deleted_at: nil) }
  scope :with_discarded, -> { unscope(where: :deleted_at) }
  scope :discarded,      -> { with_discarded.where.not(deleted_at: nil) }

  def discard!   = update_columns(deleted_at: Time.current)
  def undiscard! = update_columns(deleted_at: nil)
  def discarded? = deleted_at.present?

  # #532: final = gesperrt; andere Felder dürfen nicht geändert werden,
  # bis der Status wieder auf Entwurf gesetzt wird.
  def locked? = final?

  scope :recent, -> { order(created_at: :desc) }

  # Strukturierte Dokumente tragen Positionen; Prosa-Dokumente einen Body-KI.
  def invoice? = rechnung? || angebot?
  def prose?   = brief? || nda? || lastschrift?   # #786: Mandat ist ein Prosa-Body-Dokument

  # #694: die explizit gewählte Empfänger-Postadresse — aber nur, wenn sie
  # auch zum aktuellen Empfänger gehört (schützt vor Stale-Wahl nach
  # Empfänger-Wechsel). nil → automatisch (recipient.mailing_address).
  def chosen_recipient_address
    recipient_address if recipient_address && recipient_address.knowledge_item_uuid == recipient_uuid
  end

  # #786 Inkr.2: die fürs Mandat genutzte Bankverbindung des Schuldners
  # (= Aussteller). Gewählte, falls sie zum aktuellen Aussteller gehört;
  # sonst automatisch die erste Bankverbindung des Ausstellers.
  def effective_debtor_account
    chosen = debtor_bank_account if debtor_bank_account && debtor_bank_account.knowledge_item_uuid == issuer_uuid
    chosen || issuer&.bank_accounts&.ordered&.first
  end

  # Anrede: Override-Feld, sonst ein konservativer Default (Geschlecht/Titel
  # führen wir am KI noch nicht, daher neutral + pro Dokument überschreibbar).
  def salutation_line
    return salutation if salutation.present?
    "Sehr geehrte Damen und Herren"
  end

  # #562 (Hans): Dokument-ID für die NDA-Fußzeile: [YYYY-MM-DD-hh-mm]_[Kunde]_NDA.
  # Zeitstempel = Anlage des Dokuments (stabil je Dokument); Kunde = Empfänger,
  # dateinamenssicher (Leerraum→-, sonst nur Wort-/Bindezeichen).
  def pdf_doc_id
    stamp = (created_at || Time.current).strftime("%Y-%m-%d-%H-%M")
    kunde = recipient&.title.to_s.strip.gsub(/\s+/, "-").gsub(/[^\p{Alnum}\-_]/u, "")
    kunde = "Kunde" if kunde.blank?
    "#{stamp}_#{kunde}_NDA"
  end

  # #559 (Hans): Benennung des Dokuments. Rechnungen tragen keinen Betreff mehr —
  # ihr Name ist die Kombination aus Aussteller, Rechnungsnummer und Datum.
  # Prosa-Dokumente (Brief/NDA) behalten ihren Betreff. nil, wenn nichts da ist.
  def display_name
    if invoice?
      parts = [issuer&.title, number.presence, document_date&.strftime("%d.%m.%Y")]
      parts.compact_blank.join(" · ").presence
    else
      subject.presence
    end
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

  # ── Beträge (für Rechnung/Angebot) ───────────────────────────────────
  def net_total   = invoice_lines.sum(&:net)
  def tax_total   = vat_exempt? ? 0 : invoice_lines.sum(&:tax_amount)
  def gross_total = net_total + tax_total

  # EN16931-Steueraufschlüsselung: je Steuersatz eine Gruppe mit Netto +
  # Steuerbetrag. Sortiert nach Satz. Bei USt-Befreiung leer (keine USt).
  def tax_breakdown
    return [] if vat_exempt?
    invoice_lines.group_by { |l| l.tax_rate || 0 }.map do |rate, lines|
      net = lines.sum(&:net)
      { rate: rate, net: net, tax: net * rate / 100 }
    end.sort_by { |g| g[:rate] }
  end

  # ── #541 Compliance: Aussteller-Pflichtangaben aus dem Aussteller-KI ──────
  # Steuernummer/USt-IdNr (§14 UStG Pflicht). Liefert [[label, value], …].
  def issuer_tax_ids
    return [] unless issuer
    ids = issuer.identifiers.to_a
              .select { |i| i.label.to_s =~ /ust.?-?id|umsatzsteuer|vat|steuer\s*-?\s*(nr|nummer|id)/i }
              .map { |i| [i.label, i.value] }
    ids
  end

  # IBAN des Ausstellers (für den Zahlungsblock). Optional BIC.
  def issuer_iban = issuer&.identifiers&.to_a&.find { |i| i.label.to_s =~ /iban/i }&.value
  def issuer_bic  = issuer&.identifiers&.to_a&.find { |i| i.label.to_s =~ /\bbic\b|swift/i }&.value

  # Fortlaufende Rechnungsnummer "YYYY-NNN" — pro **Aussteller** und Jahr
  # (jeder Aussteller ist ein eigenes Rechtssubjekt mit eigenem Nummernkreis;
  # #541, Hans 2026-06-09). Lücken durch gelöschte Entwürfe sind hinnehmbar.
  def self.next_invoice_number(issuer_uuid, date = Date.current)
    return nil if issuer_uuid.blank?
    prefix = "#{date.year}-"
    last = where(kind: :rechnung, issuer_uuid: issuer_uuid).where("number LIKE ?", "#{prefix}%")
             .pluck(:number).map { |n| n.to_s.split("-").last.to_i }.max.to_i
    format("%s%03d", prefix, last + 1)
  end
end
