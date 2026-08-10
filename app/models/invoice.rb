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
  # #934: Zahlstatus. Seit #1336 Stufe 2 eine nachgeführte ABLEITUNG aus den
  # Zahlungspflichten, ohne Schreibweg aus der Oberfläche — die Spalte
  # existiert nur noch, damit „offene Eingangsbelege" in SQL filterbar bleibt.
  # NULL = keine Zahlungspflicht, also gar kein Zahlstatus: ein Bescheid oder
  # ein Vertrag ist weder offen noch bezahlt und darf in keiner Liste offener
  # Posten auftauchen.
  enum :payment_status, { offen: 0, bezahlt: 1 }
  # #1336 Stufe 1 (aus immoOS): Belegart — WAS für ein Schriftstück der Beleg
  # ist. Getrennt von `kind` (Nummernkreis/Rendering) und von `direction`.
  # NULL = nicht erfasst (Bestand). Prefix, weil `rechnung` sonst mit dem
  # gleichnamigen `kind`-Wert kollidiert.
  #
  # Die Liste ist bewusst OFFEN (Konzept „Belege, Vorgänge und ihre
  # Benennung", Abschnitt 4): eine weitere Belegart ist ein Eintrag hier
  # plus zwei Übersetzungen — keine Migration, kein neuer Programmpfad.
  # Deshalb string-hinterlegt: kein Zahlen-Mapping, das zwischen miolimOS
  # und dem immoOS-Fork auseinanderlaufen kann, und in der Datenbank steht
  # `bescheid` statt `1`.
  #
  # EINE Quelle: das Extraktions-Schema des Dokumenten-Imports liest
  # dieselbe Konstante, damit eine neue Art auch sofort erkannt wird und
  # nicht bloß von Hand wählbar ist.
  DOCUMENT_TYPES = %w[rechnung bescheid versicherung anschreiben vertrag sonstiges].freeze

  enum :document_type, DOCUMENT_TYPES.index_by(&:itself), prefix: :document_type

  has_many :invoice_lines, -> { ordered }, dependent: :destroy

  # #1336 Stufe 2: die Zahlungspflichten, die dieser Beleg TRÄGT. Der Fork
  # kann dieselbe Pflicht stattdessen an einen Vertrag hängen — dann steht sie
  # hier nicht, sondern nur unter `announced_payment_obligations`.
  has_many :payment_obligations, -> { ordered }, as: :bearer, dependent: :destroy
  # …und die, die er ANKÜNDIGT, egal wem sie gehören.
  has_many :announced_payment_obligations, -> { ordered },
           class_name: "PaymentObligation", foreign_key: :announced_by_id,
           inverse_of: :announced_by, dependent: :nullify

  validates :kind, presence: true

  # #995: nur eigene (ausgehende) Belege werden kuvertiert und frankiert.
  def frankable? = ausgehend?

  # ── Zahlungspflichten (#1336 Stufe 2) ──────────────────────────────────

  # Vorzeichen der Geldrichtung aus eigener Sicht: bei einem fremden Beleg
  # fließt Geld ab. Ein Bruttobetrag am Beleg ist immer positiv notiert; die
  # Umrechnung passiert genau hier, damit sie an keiner Rechenstelle steht.
  def obligation_sign = eingehend? ? -1 : 1

  # Die Fälligkeit des Belegs gibt es nicht mehr — bei vier Quartalsraten wäre
  # sie eine Lüge. Was es gibt, ist die nächste offene.
  def next_due_on = payment_obligations.unsettled.where.not(due_on: nil).minimum(:due_on)

  def overdue?(on = Date.current) = payment_obligations.overdue(on).exists?

  def open_amount = payment_obligations.sum { |o| o.open_amount }

  # Nachführen der Ableitungsspalte. Kein Zahlstatus ohne Zahlungspflicht —
  # damit verschwindet der Bescheid aus den offenen Posten, ohne dass jemand
  # eine Regel befolgen muss.
  def recompute_payment_status!
    obligations = payment_obligations.reload
    value =
      if obligations.empty?
        nil
      elsif obligations.all?(&:settled?)
        "bezahlt"
      else
        "offen"
      end
    update_column(:payment_status, value) unless payment_status == value
  end

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
