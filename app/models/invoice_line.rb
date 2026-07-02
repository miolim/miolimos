# #532 (Hans, 2026-06-08): eine Rechnungsposition. Netto/Steuer/Brutto
# werden aus Menge × Einzelpreis × Steuersatz berechnet — die Basis fürs
# EN16931-Mapping (#541).
class InvoiceLine < ApplicationRecord
  belongs_to :document
  # #541: Zeitbuchungen, die auf dieser Position abgerechnet sind. Wird die
  # Position gelöscht, werden sie freigegeben (invoice_line_id → nil).
  has_many :time_entries, dependent: :nullify

  scope :ordered, -> { order(:position, :id) }

  def net
    (quantity || 0) * (unit_price || 0)
  end

  def tax_amount
    net * (tax_rate || 0) / 100
  end

  def gross
    net + tax_amount
  end

  # #541 (Hans, 2026-06-09): zugeordnete Zeit-Stunden. Sind Zeiten zugeordnet,
  # IST die Menge die Summe dieser Stunden (Einheit Std) — sonst frei wählbar.
  def billed_hours = time_entries.sum { |t| t.hours }
  def time_based?  = time_entries.any?

  def recompute_quantity_from_times!
    update!(quantity: billed_hours, unit: "Std") if time_based?
  end
end
