# #1337 Schnitt 2 (aus immoOS #1021): eine Tilgung auf eine Zahlungspflicht.
#
# `amount` trägt dasselbe Vorzeichen wie die Pflicht und wie der tilgende
# Umsatz — Geldrichtung aus eigener Sicht. Mehrere Tilgungen je Pflicht bilden
# Teil- und Überzahlung ab; der getilgte Betrag der Pflicht wird daraus
# nachgeführt, nicht gesetzt.
class ObligationSettlement < ApplicationRecord
  belongs_to :payment_obligation
  # Leer bei Ausbuchung und beim Vermerk von Hand.
  belongs_to :bank_transaction, optional: true

  # `zahlung`    — durch einen Bankumsatz getilgt.
  # `ausbuchung` — Restbetrag ohne Umsatz abgeschrieben (Differenzausbuchung):
  #                das Geld kommt nicht mehr.
  # `manuell`    — von Hand als getilgt vermerkt, ohne dass ein Umsatz vorliegt.
  #                Der Fork kennt diesen Wert noch nicht; er ist nötig, weil man
  #                eine Pflicht abhaken können muss, bevor der Auszug importiert
  #                ist — und weil das etwas anderes ist als eine Ausbuchung.
  enum :kind, { zahlung: 0, ausbuchung: 1, manuell: 2 }, default: :zahlung

  validates :amount, presence: true, numericality: true
  validate  :passt_zum_umsatz

  after_commit :nachfuehren

  scope :ordered, -> { order(:settled_on, :id) }

  private

  # Ein Umsatz darf nicht mehr vergeben werden, als er hergibt — sonst wäre die
  # Zuordnung eine Behauptung über Geld, das nie geflossen ist. Die Prüfung
  # gehört hierher und nicht nur in die Auswahlliste: Im Fork stand sie nur
  # dort, und eine Sammelüberweisung ließ sich über den Dienst doppelt vergeben.
  def passt_zum_umsatz
    return if bank_transaction.blank? || amount.blank?

    bereits = bank_transaction.obligation_settlements.where.not(id: id).sum(:amount).abs
    if amount.to_d.abs + bereits > bank_transaction.amount.to_d.abs
      errors.add(:amount, :ueber_umsatz)
    end
    return if amount.to_d.zero? || bank_transaction.amount.to_d.zero?
    if amount.to_d.negative? != bank_transaction.amount.to_d.negative?
      errors.add(:amount, :falsche_richtung)
    end
  end

  # Wird die Pflicht selbst gelöscht, gehen ihre Tilgungen mit — dann gibt es
  # nichts mehr nachzuführen.
  def nachfuehren
    return if payment_obligation.blank? || payment_obligation.destroyed?
    payment_obligation.recompute_settled_amount!
  end
end
