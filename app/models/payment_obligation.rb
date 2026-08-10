# #1336 Stufe 2 (aus immoOS, Konzept „Belege, Vorgänge und ihre Benennung"):
# eine Zahlungspflicht — Betrag, Fälligkeit, Richtung. 0..n je Beleg.
#
# Sie ist bewusst NICHT als Fälligkeitszeile entworfen, sondern als der Anker,
# an dem später die Tilgung hängt (#1337): Ein Umsatz tilgt eine
# Zahlungspflicht, nicht einen Beleg — sonst ist bei mehreren Fälligkeiten je
# Beleg nicht entscheidbar, welche getilgt wurde.
#
# VORZEICHEN = Geldrichtung aus eigener Sicht. Negativ heißt „fließt von uns
# ab" (fremde Rechnung), positiv „fließt uns zu" (eigene Rechnung, erstattete
# Gutschrift). Damit hat die Pflicht dasselbe Vorzeichen wie der Umsatz, der
# sie tilgt, und keine Rechenstelle braucht eine Fallunterscheidung.
class PaymentObligation < ApplicationRecord
  # WEM die Pflicht gehört. Heute immer der Beleg; der Fork hängt hier seine
  # dauerhaften Zahlungsverhältnisse (Verträge) an.
  belongs_to :bearer, polymorphic: true
  # WORAUF sie steht — das Schreiben, das sie ankündigt. Optional, weil eine
  # Pflicht aus einem Verhältnis entstehen kann, ohne dass ein Beleg vorliegt.
  belongs_to :announced_by, class_name: "Invoice", optional: true

  # #1337 Schnitt 2: die Tilgungen. Eigene Tabelle, kein Fremdschlüssel hier —
  # nur so sind Teilzahlung, Überzahlung und die Sammelüberweisung abbildbar,
  # die mehrere Pflichten tilgt.
  has_many :obligation_settlements, -> { ordered }, dependent: :destroy

  validates :amount, presence: true

  # Der Zahlstatus des Trägers ist eine Ableitung — sie wird hier nachgeführt,
  # nicht irgendwo von Hand gesetzt.
  after_save    :refresh_bearer_payment_status
  after_destroy :refresh_bearer_payment_status

  # Ohne Fälligkeit ans Ende — „unbestimmt" ist nicht „sofort".
  scope :ordered,   -> { order(Arel.sql("due_on ASC NULLS LAST")).order(:position, :id) }
  scope :unsettled, -> { where("amount <> settled_amount") }
  scope :overdue,   ->(on = Date.current) { unsettled.where(due_on: ...on) }
  scope :borne_by,  ->(record) { where(bearer: record) }

  def open_amount = (amount || 0) - (settled_amount || 0)
  def settled?    = open_amount.zero?

  # Vier Werte, vorzeichenrichtig. Eine Gutschrift ist negativ und wird durch
  # eine negative Erstattung getilgt; eine Prüfung, die einen positiven Betrag
  # voraussetzt, hielte sie für unbezahlt (der Fehler aus #1329).
  def state
    return :bezahlt    if open_amount.zero? && !amount.zero?
    return :offen      if settled_amount.zero?
    return :ueberzahlt if settled_amount.abs > amount.abs
    :teilweise
  end

  def overdue?(on = Date.current) = !settled? && due_on.present? && due_on < on

  # #1337 Schnitt 2: `settled_amount` ist jetzt eine nachgeführte ABLEITUNG aus
  # den Tilgungen — dieselbe Spalte wie in #1336, kein Umbau, aber ohne
  # direkten Schreibweg. Sie bleibt als Spalte, damit „offene Pflichten" in SQL
  # filterbar sind, ohne den halben Bestand in den Speicher zu laden.
  def recompute_settled_amount!
    summe = obligation_settlements.sum(:amount)
    update_column(:settled_amount, summe) unless settled_amount == summe
    bearer&.recompute_payment_status! if bearer.respond_to?(:recompute_payment_status!)
  end

  # Von Hand als getilgt vermerken, ohne dass ein Umsatz vorliegt — der Auszug
  # ist noch nicht importiert, die Zahlung aber geleistet. Läuft über dieselbe
  # Tabelle wie alles andere, damit es genau EINEN Schreibweg gibt.
  def settle_fully!
    rest = open_amount
    return if rest.zero?
    obligation_settlements.create!(kind: :manuell, amount: rest, settled_on: Date.current)
  end

  # Nimmt die Vermerke von Hand zurück. Tilgungen aus Bankumsätzen bleiben —
  # sie sind Tatsachen, kein Häkchen.
  def unsettle! = obligation_settlements.manuell.destroy_all

  private

  def refresh_bearer_payment_status
    bearer.recompute_payment_status! if bearer.respond_to?(:recompute_payment_status!)
  end
end
