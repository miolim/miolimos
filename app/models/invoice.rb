# #926 (Hans, 2026-07-09): Rechnung/Angebot als EIGENE strukturierte Entität —
# vorher ein kind des Sammel-Modells Document. Trägt Positionen
# (invoice_lines), aus denen sich Netto/Steuer/Brutto + die EN16931-
# Steueraufschlüsselung (#541) ergeben; Nummernkreis pro Aussteller.
# Parteien, Infoblock, Artefakte, Sperre kommen aus Printable; gerendert
# wird über dasselbe Verfahren (DocumentRenderer) wie das Anschreiben.
class Invoice < ApplicationRecord
  # #602 S1: sichtbar = eigene Rechnungen + Rechnungen sichtbarer Topics.
  include VisibleVia
  visible_via topic_column: :topic_id
  include Printable

  enum :kind, { rechnung: 0, angebot: 1 }
  # #934: Richtung — ausgehend (wir stellen aus, Nummernkreis + Rendering)
  # oder eingehend (fremder Beleg aus dem Dokumenten-Import; das Original-
  # PDF hängt als Artefakt, die Nummer kommt vom Aussteller).
  enum :direction, { ausgehend: 0, eingehend: 1 }, default: :ausgehend
  # #934: Zahlstatus für Eingangsrechnungen (minimal, Skonto etc. später).
  enum :payment_status, { offen: 0, bezahlt: 1 }, default: :offen

  has_many :invoice_lines, -> { ordered }, dependent: :destroy

  validates :kind, presence: true

  # #995: nur eigene (ausgehende) Belege werden kuvertiert und frankiert.
  def frankable? = ausgehend?

  # #972 (aus immoos übernommen, #1057): Rechnungen, an denen ein Kontakt
  # (Person/Org-KI) als Aussteller ODER Empfänger beteiligt ist — für den
  # „Rechnungen“-Tab am Kontakt. Eingang (eingehend) = Kontakt ist Aussteller,
  # Ausgang (ausgehend) = Kontakt ist Empfänger.
  def self.for_party(ki_uuid)
    return none if ki_uuid.blank?
    where(issuer_uuid: ki_uuid).or(where(recipient_uuid: ki_uuid))
                               .order(document_date: :desc)
  end

  # #559 (Hans): Benennung = Aussteller · Rechnungsnummer · Datum.
  def display_name
    parts = [issuer&.title, number.presence, document_date&.strftime("%d.%m.%Y")]
    parts.compact_blank.join(" · ").presence
  end

  # ── Beträge ───────────────────────────────────────────────────────────
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

  # Fortlaufende Rechnungsnummer "YYYY-NNN" — pro **Aussteller** und Jahr
  # (jeder Aussteller ist ein eigenes Rechtssubjekt mit eigenem Nummernkreis;
  # #541, Hans 2026-06-09). Lücken durch gelöschte Entwürfe sind hinnehmbar.
  def self.next_number(issuer_uuid, date = Date.current)
    return nil if issuer_uuid.blank?
    prefix = "#{date.year}-"
    last = where(kind: :rechnung, direction: :ausgehend, issuer_uuid: issuer_uuid).where("number LIKE ?", "#{prefix}%")
             .pluck(:number).map { |n| n.to_s.split("-").last.to_i }.max.to_i
    format("%s%03d", prefix, last + 1)
  end

  # #926 Stufe 2: Rechnungs-spezifische Merge-Schlüssel.
  def merge_context
    super.merge({
      "betreff"          => subject.presence,
      "nummer"           => number.presence,
      "rechnungsnummer"  => number.presence,
      "nettobetrag"      => format("%.2f", net_total.to_f),
      "gesamtbetrag"     => format("%.2f", gross_total.to_f)
    }.compact)
  end
end
