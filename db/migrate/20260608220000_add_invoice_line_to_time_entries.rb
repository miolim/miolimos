# #541 (Hans, 2026-06-08): Zeitbuchungen einer Rechnungsposition zuordnen.
# Gesetzt = die Zeit ist auf dieser Position abgerechnet (kein Doppel-
# Abrechnen). Beim Löschen der Position wird die Zuordnung genullt
# (dependent: :nullify im Modell), die Zeit ist wieder abrechenbar.
class AddInvoiceLineToTimeEntries < ActiveRecord::Migration[8.1]
  def change
    add_reference :time_entries, :invoice_line, null: true, foreign_key: true
  end
end
