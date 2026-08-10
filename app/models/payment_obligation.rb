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

  # Solange es upstream keine Umsätze gibt, ist „bezahlt" eine Handlung an der
  # Pflicht. Mit #1337 wird `settled_amount` aus der Tilgungstabelle
  # nachgeführt — dieselbe Spalte, kein Umbau.
  def settle_fully!  = update!(settled_amount: amount)
  def unsettle!      = update!(settled_amount: 0)

  private

  def refresh_bearer_payment_status
    bearer.recompute_payment_status! if bearer.respond_to?(:recompute_payment_status!)
  end
end
